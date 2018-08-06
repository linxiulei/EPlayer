//
//  ViewController.swift
//  EPlayer
//
//  Created by 林守磊 on 16/03/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

import UIKit
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit.UIGestureRecognizerSubclass

import os
import os.log

class PanRecognizerWithInitialTouch : UIPanGestureRecognizer  {
    var initialTouchLocation: CGPoint!
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        initialTouchLocation = touches.first!.location(in: view)
    }
}

let MOVE_STEP: Int64 = 2000

#if targetEnvironment(simulator)
let epdict: EPDictionary? = nil
#else
let epdict = EPDictionary("", "")
#endif

class MovieViewController: UIViewController, UIGestureRecognizerDelegate {
    override var prefersStatusBarHidden: Bool {
        get {
            return statusBarIsHidden
        }
    }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        get {
            return UIStatusBarAnimation.slide
        }
    }
    override var preferredStatusBarStyle: UIStatusBarStyle {
        get {
            return UIStatusBarStyle.lightContent
        }
    }
    
    // MARK: Properties
    
    var video: Video!
    var movieFileManager: MovieFileManager?
    var isUIHidden = false
    var progressView: MovieProgress!
    var oriVolume: Float = 0
    var oriBrt: CGFloat = 0
    var volumeView = MPVolumeView()
    var volume: UISlider?
    var updateTimer: Timer?
    var layer: AVSampleBufferDisplayLayer?
    var statusBarIsHidden = false
    let s = AVAudioSession()
    var moviePanelController: MoviePanelController?
    
    @IBOutlet var leftSwipe: UISwipeGestureRecognizer!
    @IBOutlet var rightSwipe: UISwipeGestureRecognizer!
    @IBOutlet var panGesture: PanRecognizerWithInitialTouch!
    @IBOutlet var singleTap: UITapGestureRecognizer!
    @IBOutlet var doubleTap: UITapGestureRecognizer!
    
    @IBOutlet weak var panelContainerView: UIView!
    @IBOutlet weak var filenameLabel: UILabel!
    @IBOutlet weak var notifyLabel: UILabel!
    @IBOutlet weak var nextBtn: UIButton!
    @IBOutlet weak var prevBtn: UIButton!
    @IBOutlet weak var paraLabel: UILabel!
    @IBOutlet weak var backBtn: UIButton!
    @IBOutlet weak var movieView: UIImageView!
    @IBOutlet weak var playBtn: UIButton!
    @IBOutlet weak var subtitleView: UILabel!
    @IBOutlet weak var elaspedTimeLabel: UILabel!
    @IBOutlet weak var remainedTimeLabel: UILabel!
    
    @IBAction func click(_ sender: UIButton, forEvent event: UIEvent) {
        if (video.getStatus() == PlayStatus.pause) {
            sender.setTitle("playing", for: UIControlState.normal)
            video.play()
        } else {
            sender.setTitle("pause", for: UIControlState.normal)
            video.pause()
        }
    }
    
    @IBAction func clickPrev(_ sender: UIButton, forEvent event: UIEvent) {
        guard let movieFileManager = movieFileManager else {
            os_log("movieFileManager is not set", type: .error)
            return
        }
        video.pause()
        var fileIndex = movieFileManager.getCurIndex()
        while (fileIndex > 0) {
            fileIndex = fileIndex - 1
            let nextMovieFile = movieFileManager.getMovieFileByIndex(fileIndex)
            if !nextMovieFile.isMovie() {
                continue
            }
            movieFileManager.setCurIndex(fileIndex)
            movieFileManager.saveState()
            video.stop()
            video.deinit0()
            
            progressView.value = 0
            video = Video(path: nextMovieFile.path,
                          view: movieView,
                          sView: subtitleView,
                          pView: paraLabel,
                          dict: epdict,
                          alayer: layer!)
            moviePanelController?.reload()
            filenameLabel.text = nextMovieFile.getName()
            video.play()
            break
        }
        /*
        performSegue(withIdentifier: "unwindSegueToFileTable", sender: self)
        print("no more videos")
         */
    }
    
    @IBAction func clickNext(_ sender: UIButton, forEvent event: UIEvent) {
        _ = playNext()
    }

    func playNext() -> Bool {
        if (video.playStatus == PlayStatus.playing) {
            video.pause()
        }
        guard let movieFileManager = movieFileManager else {
            os_log("movieFileManager is not set", type: .error)
            return false
        }
        
        var fileIndex = movieFileManager.getCurIndex()
        while(fileIndex < (movieFileManager.getFileCount() - 1)) {
            fileIndex = fileIndex + 1
            let nextMovieFile = movieFileManager.getMovieFileByIndex(fileIndex)
            if !nextMovieFile.isMovie() {
                continue
            }
            movieFileManager.setCurIndex(fileIndex)
            movieFileManager.saveState()
            video.stop()
            video.deinit0()
            
            progressView.value = 0

            video = Video(path: nextMovieFile.path,
                          view: movieView,
                          sView: subtitleView,
                          pView: paraLabel,
                          dict: epdict,
                          alayer: layer!)
            moviePanelController?.reload()
            filenameLabel.text = nextMovieFile.getName()
            video.play()
            return true
        }
        return false
    }
    
    @IBAction func handleOneTap(_ sender: UITapGestureRecognizer) {
        if (sender.state == UIGestureRecognizerState.ended)
        {
            if (isUIHidden) {
                playBtn.isHidden = false
                backBtn.isHidden = false
                progressView?.isHidden = false
                isUIHidden = false
                nextBtn.isHidden = false
                prevBtn.isHidden = false
                filenameLabel.isHidden = false
                statusBarIsHidden = false
                moviePanelController?.view.isHidden = false
                panelContainerView.isUserInteractionEnabled = true
                elaspedTimeLabel.isHidden = false
                remainedTimeLabel.isHidden = false
            } else {
                playBtn.isHidden = true
                backBtn.isHidden = true
                progressView?.isHidden = true
                isUIHidden = true
                nextBtn.isHidden = true
                prevBtn.isHidden = true
                filenameLabel.isHidden = true
                statusBarIsHidden = true
                moviePanelController?.view.isHidden = true
                panelContainerView.isUserInteractionEnabled = false
                elaspedTimeLabel.isHidden = true
                remainedTimeLabel.isHidden = true
            }
            setNeedsStatusBarAppearanceUpdate()
            os_log("hanle one tap")
        }
    }
    
    @IBAction func handleTwoTaps(_ sender: UITapGestureRecognizer) {
        if (sender.state == UIGestureRecognizerState.ended)
        {
            if (video.getStatus() == PlayStatus.pause) {
                playBtn.setTitle("playing", for: UIControlState.normal)
                video.play()
            } else {
                playBtn.setTitle("pause", for: UIControlState.normal)
                video.pause()
            }
        }
    }
    
    @IBAction func handleLeftSwipe(_ sender: UISwipeGestureRecognizer) {
        let pts = video.getMoviePosition()
        moveMovie(pts - MOVE_STEP)
    }
    @IBAction func handleRightSwipe(_ sender: UISwipeGestureRecognizer) {
        let pts = video.getMoviePosition()
        moveMovie(pts + MOVE_STEP)
    }
    
    @IBAction func handlePan(_ sender: PanRecognizerWithInitialTouch) {
        let translation = sender.translation(in: self.view)
        
        if (isOnRightWindow(sender.initialTouchLocation)) {
            if (sender.state == .began) {
                oriVolume = getVolume()
            }
            if (sender.state == .changed) {
                self.setVolume(Float(translation.y) / -220.0 + self.oriVolume)
            }
        } else {
            if (sender.state == .began) {
                oriBrt = UIScreen.main.brightness
            }
            if (sender.state == .changed) {
                UIScreen.main.brightness = (translation.y / -250.0) + oriBrt
            }
        }
    }

    func setVolume(_ value: Float) {
        let oldVolume = getVolume()
        if (abs(value - oldVolume) < 0.08) {
            return
        }
        volume?.setValue(value, animated: false)
    }
    
    func getVolume() -> Float {
        return s.outputVolume
    }
    

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        if (touch.view == progressView) {
            return false
        }  else if (!isUIHidden ) {
            if (touch.view!.isDescendant(of: moviePanelController!.view)) {
                return false
            }
        }
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        volume = volumeView.subviews.first as? UISlider
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = self
        panGesture.require(toFail: leftSwipe)
        panGesture.require(toFail: rightSwipe)
        panGesture.delegate = self
        
        guard let moviePanelController = childViewControllers.first as? MoviePanelController else {
            os_log("Didn't find movie panel controller")
            return
        }
        moviePanelController.rootMovieController = self
        self.moviePanelController = moviePanelController
        
        //let value = UIInterfaceOrientation.landscapeLeft.rawValue
        //UIDevice.current.setValue(value, forKey: "orientation")
        //UIViewController.attemptRotationToDeviceOrientation()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        

        var a = Date().timeIntervalSince1970
        guard let movieFileManager = movieFileManager else {
            return
        }
        
        let movieFile = movieFileManager.getCurMovieFile()
        let progress = movieFile.getProgress()

        layer = createAVLayer()
        var b = Date().timeIntervalSince1970
        os_log("creating layer uses %f", type: .debug,  b - a)
        
        a = Date().timeIntervalSince1970
        guard let video = Video(path: movieFile.path,
            view: movieView,
            sView: subtitleView,
            pView: paraLabel,
            dict: epdict,
            alayer: layer!
            ) else {
                self.notify("Failed to open video")
                self.performSegue(withIdentifier: "unwindSegueToFileTable", sender: self)
                return
        }
        
        self.video = video
        // process files
        
        if (progress > 0) {
            let moveToInMS = Int64(progress) * video.getMovieDuration() / 100
            moveMovie(moveToInMS)
        }
        
        filenameLabel.text = movieFile.getName()

        b = Date().timeIntervalSince1970
        os_log("init video use %f", type: .debug, b - a)
        a = Date().timeIntervalSince1970
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let pos = self.video.getMoviePosition()
            self.progressView.value = Float(pos) / 1000
            let percent = self.video.getMoviePositionInPercent()
            movieFileManager.getCurMovieFile().setProgress(percent)
            
            let elaspedTimeString = convertMStoString(pos)
            let remainedTimeString = convertMStoString(self.video.getMovieDuration() - pos)
            self.elaspedTimeLabel.text = elaspedTimeString
            self.remainedTimeLabel.text = remainedTimeString
            if (self.video.playStatus == PlayStatus.stopped && self.video.videoIsEOF) {
                let ret = self.playNext()
                if (!ret) {
                    print("no more videos")
                    self.updateTimer!.invalidate()
                    self.performSegue(withIdentifier: "unwindSegueToFileTable", sender: self)
                }
            }
        }

        b = Date().timeIntervalSince1970
        os_log("creating queue uses %f", type: .debug,  b - a)
        a = Date().timeIntervalSince1970

        video.play()
        b = Date().timeIntervalSince1970
        os_log("pausing uses %f", type: .debug,  b - a)

        movieView.contentMode = .scaleAspectFit
        movieView.backgroundColor = UIColor.black
        
        progressView = MovieProgress(video)
        //progressView.setThumbImage(UIImage(named: "circle1.png"), for: .normal)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        let leadingConstraint = NSLayoutConstraint(item: progressView, attribute: .leading,
                                                   relatedBy: .equal, toItem: movieView,
                                                   attribute: .leading, multiplier: 1, constant: 50)
        let trailingConstraint = NSLayoutConstraint(item: progressView, attribute: .trailing,
                                                    relatedBy: .equal, toItem: movieView,
                                                    attribute: .trailing, multiplier: 1, constant: -50)
        let bottomConstraint = NSLayoutConstraint(item: progressView, attribute: .bottom,
                                                  relatedBy: .equal, toItem: movieView,
                                                  attribute: .bottom, multiplier: 1, constant: -8)
        progressView.minimumValue = 0
        progressView.maximumValue = Float(video.getMovieDuration() / 1000)
        progressView.isContinuous = true
        progressView.tintColor = UIColor.green
        progressView.addTarget(self,
                               action: #selector(MovieViewController.sliderValueDidChange(_ :)),
                               for: .valueChanged)
        movieView.isUserInteractionEnabled = true
        movieView.addSubview(progressView)
        movieView.addConstraints([bottomConstraint, leadingConstraint, trailingConstraint])
 
        b = Date().timeIntervalSince1970
        print("create views \(b - a)")
        

        movieView.layer.insertSublayer(layer!, at: 0)
        
        moviePanelController!.reload()
    }
    
    func downloadSubtitles() {
        video.downloadSubtitles() {
            self.moviePanelController!.reload()
        }
    }
    
    @objc func sliderValueDidChange(_ sender: MovieProgress!) {
        os_log("seeking slider")
        moveMovie(Int64(sender.value * 1000))
    }
    
    func moveMovie(_ msec: Int64) {
        video.seekTsInMSec = msec
        video.seekReq = true
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func notify(_ msg: String) {
        notifyLabel.text = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.notifyLabel.text = ""
        }
    }

}


func setAudioDesc(_ desc: UnsafeMutablePointer<AudioStreamBasicDescription>,
                  _ video: Video) {
    let dataSize = UInt32(av_get_bytes_per_sample(AV_SAMPLE_FMT_S16))
    let sampleRate = Double(video.aCodecCtx!.pointee.sample_rate)
    //let channels = UInt32(video.aCodecCtx!.pointee.channels)
    // I converted audito to 2-channels format
    let channels = UInt32(2)
    
    desc.pointee.mSampleRate = sampleRate
    //desc.pointee.mSampleRate = 32000
    desc.pointee.mFormatID = AudioFormatID(kAudioFormatLinearPCM)
    desc.pointee.mFormatFlags = AudioFormatFlags(kAudioFormatFlagIsSignedInteger |
                                                 kAudioFormatFlagsNativeEndian |
                                                 kAudioFormatFlagIsPacked)
    desc.pointee.mBitsPerChannel = dataSize * 8
    desc.pointee.mChannelsPerFrame = channels
    desc.pointee.mFramesPerPacket = 1
    desc.pointee.mBytesPerFrame = dataSize * channels
    desc.pointee.mBytesPerPacket = dataSize * channels
    desc.pointee.mReserved = 0
}

func isOnRightWindow(_ point: CGPoint) -> Bool {
    return point.x > UIScreen.main.bounds.width / 2
}

func createAVLayer() -> AVSampleBufferDisplayLayer {
    let layer = AVSampleBufferDisplayLayer()
    layer.bounds = UIScreen.main.bounds
    layer.position = CGPoint(x: CGFloat(layer.bounds.width / 2), y: CGFloat(layer.bounds.height / 2))
    layer.videoGravity = AVLayerVideoGravity.resizeAspect
    layer.backgroundColor = UIColor.black.cgColor
    
    //set Timebase
    let _CMTimebasePointer = UnsafeMutablePointer<CMTimebase?>.allocate(capacity: 1)
    CMTimebaseCreateWithMasterClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), _CMTimebasePointer)
    
    layer.controlTimebase = _CMTimebasePointer.pointee
    CMTimebaseSetTime(layer.controlTimebase!, CMTimeMake(1, 1))
    CMTimebaseSetRate(layer.controlTimebase!, 0.0)
    return layer
}



