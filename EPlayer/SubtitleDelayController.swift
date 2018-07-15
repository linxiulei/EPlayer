//
//  SubtitleDelayController.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/4/14.
//  Copyright © 2018 林守磊. All rights reserved.
//

import Foundation

class SubtitleDelayController: UIViewController {
    var video: Video?
    
    @IBOutlet weak var delayLabel: UILabel!
    @IBOutlet weak var bigStepbackBtn: UIButton!
    @IBOutlet weak var stepbackBtn: UIButton!
    @IBOutlet weak var stepforwardBtn: UIButton!
    @IBOutlet weak var bigStepForwardBtn: UIButton!
    @IBOutlet weak var resetBtn: UIButton!
    
    @IBAction func delayBtnOnClick(_ sender: UIButton) {
        guard let video = video else {
            return
        }
        let oldOffset = video.subtitleOffset
        if (sender == bigStepbackBtn) {
            video.setSubtitleOffset(oldOffset - 1000)
        } else if (sender == stepbackBtn) {
            video.setSubtitleOffset(oldOffset - 100)
        } else if (sender == stepforwardBtn) {
            video.setSubtitleOffset(oldOffset + 100)
        } else if (sender == bigStepForwardBtn) {
            video.setSubtitleOffset(oldOffset + 1000)
        } else if (sender == resetBtn) {
            video.setSubtitleOffset(0)
        }
        showDelayLabel()
    }
    
    func showDelayLabel() {
        guard let video = video else {
            return
        }
        
        let offsetAbs = abs(Float(video.subtitleOffset) / 1000.0)
        if (video.subtitleOffset > 0) {
            delayLabel.text = "ahead of \(offsetAbs)s"
        } else {
            delayLabel.text = "delay of \(offsetAbs)s"
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        showDelayLabel()
    }
}
