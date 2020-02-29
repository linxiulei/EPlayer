//
//  Video.swift
//  EPlayer
//
//  Created by 林守磊 on 17/03/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import Foundation
import os.log
import AudioToolbox
import AVFoundation

typealias SwsContext = OpaquePointer
typealias AssLibrary = OpaquePointer
typealias AssRenderer = OpaquePointer
typealias AssTrack = OpaquePointer

let AVERROR_EOF = -541478725
let FMT_CONVERT_TO = AV_PIX_FMT_BGRA
let CVPIX_FMT = kCVPixelFormatType_32BGRA

let AUDIO_FMT_CONVERT_TO = AV_SAMPLE_FMT_S16

let ALIGN = Int32(64)
let CODEC_HWAccel = [AV_CODEC_ID_H263, AV_CODEC_ID_H264]
//let FMT_CONVERT_TO = AV_PIX_FMT_UYVY422

//let FMT_CONVERT_TO = AV_PIX_FMT_YUV420P
//let CVPIX_FMT = kCVPixelFormatType_420YpCbCr8Planar

// using 19% CPU
//let FMT_CONVERT_TO = AV_PIX_FMT_YUYV422
//let CVPIX_FMT = kCVPixelFormatType_422YpCbCr8_yuvs
//

let MAX_SUBTITLES = 10

enum PlayStatus {
    case started
    case playing
    case pause
    case stopped
    case ended
}

enum ClockSource {
    case Video
    case Audio
    case External
}

var flushPacket = AVPacket()
var EOFPacket = AVPacket()

func void() {}


func ass_msg_cb(_ level: Int32, _ fmt: UnsafePointer<Int8>?, _ va: CVaListPointer, _ data: UnsafeMutableRawPointer?) -> () {}

enum MovieError {
    case FileOpenError(msg: String)
}
class Video {

    let AV_NOPTS_VALUE: UInt64 = 0x8000000000000000
    let AV_TIME_BASE: Int = 1000000
    var AV_TIME_BASE_Q = AVRational()

    var filepath = ""
    var pFormatCtx: UnsafeMutablePointer<AVFormatContext>?

    var pCodec: UnsafeMutablePointer<AVCodec>?
    var pCodecCtx: UnsafeMutablePointer<AVCodecContext>?
    var videoStream: Int32! = -1
    var vStream: UnsafeMutablePointer<AVStream>?
    var _videoTimer: Timer?
    var _displayTimer: Timer?
    var vCurPts: Int64 = 0
    var duration: Int64 = 0

    var swFrame: UnsafeMutablePointer<AVFrame>?
    var pFrameRGB: UnsafeMutablePointer<AVFrame>?

    var aCodec: UnsafeMutablePointer<AVCodec>?
    var aCodecCtx: UnsafeMutablePointer<AVCodecContext>?
    var audioStream: Int32! = -1
    var aStream: UnsafeMutablePointer<AVStream>?
    var _audioQueue: AudioQueueRef?
    var aCurPts: Int64 = 0
    var aCurTime: Double = 0
    var audioQueueNum: Int = 2
    var audioFramePerQueue: Int = 4
    var srcChannels: Int32 = 0
    var aStreamNameIndex = [String: UInt32]()

    var sCodec: UnsafeMutablePointer<AVCodec>?
    var sCodecCtx: UnsafeMutablePointer<AVCodecContext>?
    var subtitleStream: Int32! = -1
    var sCurPts: Int64 = 0
    var subtitleName: String?
    var subtitleOffset: Int64 = 0
    var sStreamNameIndex = [String: UInt32]()

    var assLibrary : AssLibrary?
    var assRenderer: AssRenderer?
    var assTrack: UnsafeMutablePointer<ASS_Track>?
    var draw = FFDrawContext()

    var curSubFrame:  AVSubtitle?
    var curSubImgArray = [UnsafeMutablePointer<ASS_Image>]()
    var curSubText: String?

    var sws_ctx: SwsContext!

    var width: Int32!
    var height: Int32!

    var audioQueue = AVPacketQueue<AVPacket>(0)
    var videoQueue = AVPacketQueue<AVFrame>(0)
    var subtitleQueue = AVPacketQueue<AVPacket>(0)
    var swrCtx:  OpaquePointer?
    var swrCtxComp:  OpaquePointer!

    var videoPts: UInt64 = 0
    var audioPts: UInt64 = 0
    var subPts: UInt64 = 0
    var lastVideoPTS: Int64 = 0
    var lastDelay: UInt64 = 0

    var playStatus: PlayStatus = PlayStatus.started

    var seekReq = false
    var seekTsInMSec: Int64 = 0

    var displayView: UIImageView
    var subtitleView: UILabel
    var paraView: UILabel
    var sideSubtitleView: UILabel

    let myShadow = NSShadow()
    var decodeThreadIsStopped = true

    var clockSource = ClockSource.Audio
    var lastDisplayTS: Double = 0

    var lastImage: UIImage?
    var lastAT: NSAttributedString?
    var lastPara: NSAttributedString?
    var lastSideSubtitle: NSAttributedString?

    var mdict: EPDictionary?
    var subtitleManager = SubtitleManager()
    var subtitleAttr: [NSAttributedStringKey: Any]
    var paraAttr: [NSAttributedStringKey: Any]
    var layer: AVSampleBufferDisplayLayer
    var cvPixelBufferPool: CVPixelBufferPool?
    #if targetEnvironment(simulator)
        /*
         * Simulator doesn't implement hwaccel well
         */
        var usingHWAccel = false
    #else
    // though videotoolbox don't support some encodings like DivX
        var usingHWAccel = true
    #endif
    var videoIsEOF = false
    init?(path: String, view: UIImageView, sView: UILabel, pView: UILabel, ssView: UILabel, dict: EPDictionary?, alayer: AVSampleBufferDisplayLayer) {
        let a = Date().timeIntervalSince1970
        mdict = dict
        displayView = view
        subtitleView = sView
        paraView = pView
        sideSubtitleView = ssView
        layer = alayer


        AV_TIME_BASE_Q.den = 1000000
        AV_TIME_BASE_Q.num = 1

        myShadow.shadowBlurRadius = 3
        myShadow.shadowOffset = CGSize(width: 0, height: -1)
        myShadow.shadowColor = UIColor.black

        let fontSize = UIScreen.main.bounds.size.width / 35
        let style = NSMutableParagraphStyle()
        style.alignment = NSTextAlignment.center

        subtitleAttr = [
            NSAttributedStringKey.foregroundColor: UIColor.white,
            NSAttributedStringKey.shadow: myShadow,
            NSAttributedStringKey.font: UIFont.boldSystemFont(ofSize: fontSize),
            NSAttributedStringKey.paragraphStyle: style]

        let style1 = NSMutableParagraphStyle()
        style1.alignment = NSTextAlignment.right

        paraAttr = [
            NSAttributedStringKey.foregroundColor: UIColor.white,
            NSAttributedStringKey.shadow: myShadow,
            NSAttributedStringKey.font: UIFont.boldSystemFont(ofSize: fontSize),
            NSAttributedStringKey.paragraphStyle: style1]


        self.filepath = path
        os_log("Video open file %@", type: .info, path)
        var ret: Int32 = avformat_open_input(&pFormatCtx, path, nil, nil)
        if isErr(ret, "avformat_open_input") {
            return nil
        }
        var b = Date().timeIntervalSince1970
        os_log("open input uses %f", type: .debug, b - a)


        ret = avformat_find_stream_info(pFormatCtx, nil)
        if isErr(ret, "avformat_find_stream_info") {
            return nil
        }
        duration = pFormatCtx!.pointee.duration / 1000
        b = Date().timeIntervalSince1970
        os_log("find stream uses %f", type: .debug, b - a)

        av_dump_format(pFormatCtx, 0, path, 0);
        b = Date().timeIntervalSince1970
        os_log("dump format uses %f", type: .debug, b - a)
        ret = vDecInit()
        if isErr(ret, "vDecInit") {
            return nil
        }
        b = Date().timeIntervalSince1970
        os_log("video decode init uses %f", type: .debug, b - a)

        ret = aDecInit()
        if isErr(ret, "aDecInit") {
            return nil
        }
        b = Date().timeIntervalSince1970
        os_log("audio decode init uses %f", type: .debug, b - a)

        subtitleManager.mdict = mdict

        // Don't need to deal the situation of no subtitles
        _ = sDecInit()

        b = Date().timeIntervalSince1970
        os_log("subtitle decode init uses %f", type: .debug, b - a)

        b = Date().timeIntervalSince1970
        initExternalSubtitles(filepath)
        os_log("external subtitles init uses %f", type: .debug, b - a)

        let subtitleStreamNames = subtitleManager.getSubtitleStreamNames()
        if subtitleStreamNames.count > 0 {
            setSubtitleStreamByName(subtitleStreamNames[0])
        }

        srcChannels = aCodecCtx!.pointee.channels
        // TODO: I didn't set AudioQueue properly to channel layout
        // other than "stereo" yet, so I hardcode it as stereo
        swrCtx = swr_alloc_set_opts(
            nil,
            //av_get_default_channel_layout(aCodecCtx!.pointee.channels),
            Int64(av_get_channel_layout("stereo")),
            AUDIO_FMT_CONVERT_TO,
            aCodecCtx!.pointee.sample_rate,
            av_get_default_channel_layout(aCodecCtx!.pointee.channels),
            aCodecCtx!.pointee.sample_fmt,
            aCodecCtx!.pointee.sample_rate,
            0,
            nil)
        if (swrCtx == nil) {
            os_log("failed to alloc swr", type: .error)
            return nil
        }

        ret = swr_init(swrCtx)
        if isErr(ret, "swrCtx init") {
            return nil
        }


        layer.requestMediaDataWhenReady(on: DispatchQueue(label: "layer"), using: { () -> Void in
            if (self.videoQueue.isEmpty) {
                os_log("video queue is empty, sleep 100ms", type: .info)
                usleep(100 * 1000)
            }
            self.displayLayer()
        })

        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now()) {
            self.decode_thread()
        }

        startAudioQueue()

        pause()
    }

    func tryReinitSwrCtxByFrame(_ frame: UnsafeMutablePointer<AVFrame>) {
        if (srcChannels == frame.pointee.channels) {
            return
        }
        srcChannels = frame.pointee.channels
        swr_free(&swrCtx)
        swrCtx = swr_alloc_set_opts(
            nil,
            //av_get_default_channel_layout(aCodecCtx!.pointee.channels),
            Int64(av_get_channel_layout("stereo")),
            AUDIO_FMT_CONVERT_TO,
            aCodecCtx!.pointee.sample_rate,
            av_get_default_channel_layout(frame.pointee.channels),
            aCodecCtx!.pointee.sample_fmt,
            frame.pointee.sample_rate,
            0,
            nil)

        if (swrCtx == nil) {
            os_log("failed to alloc swr", type: .error)
        }

        let ret = swr_init(swrCtx)
        if isErr(ret, "swrCtx init") {
            return
        }
    }
    // offset in millisecond,
    // it means use subtitle before video if it is less than 0
    // it means use subtitle after video if it is big than 0
    func setSubtitleOffset(_ offset: Int64) {
        guard let subtitleName = subtitleName else {
            return
        }
        subtitleOffset = offset
        subtitleManager.flush(subtitleName)
    }

    func downloadSubtitles(closure: @escaping () -> Void) {
        var subtitleID = ["chi": 0,
                          "eng": 0]
        createSubtitleDirectory()

        subtitleManager.initLibass(width, height)

        for lang in subtitleID.keys {
            OpenSubtitlesAPI().downloadSubtitles(filepath, lang) { (_ subinfo: Subinfo) in
                if (subtitleID[lang]! > MAX_SUBTITLES) {
                    return
                }
                self.subtitleDownloadCallback(subinfo, "\(subtitleID[lang]!)")
                subtitleID[lang]! += 1
                closure()
            }
        }

        for lang in ["chi"] {
            XLAPI().downloadSubtitles(filepath, lang) { (_ subinfo: Subinfo) in
                if (subtitleID[lang]! > MAX_SUBTITLES) {
                    return
                }
                self.subtitleDownloadCallback(subinfo, "\(subtitleID[lang]!)")
                subtitleID[lang]! += 1
                closure()
            }
        }

        /*
        ShooterAPI().downloadSubtitles(filepath, "eng") { (_ subinfo: Subinfo) in
            if (subtitleID > MAX_SUBTITLES) {
                return
            }
            self.subtitleDownloadCallback(subinfo, "\(subtitleID)")
            subtitleID += 1
            closure()
        }
         */

    }

    func subtitleDownloadCallback(_ subinfo: Subinfo, _ suffix: String) {
        guard let data = subinfo.data else {
            os_log("no data found in subinfo", type: .debug)
            return
        }

        let subtitleName = subinfo.langs.joined(separator: "&") + ".\(suffix)." + subinfo.ext
        let subtitlePath = self.getSubtitleDirectory() + "/" + subtitleName
        FileManager.default.createFile(
            atPath: subtitlePath,
            contents: data,
            attributes: nil)

        self.subtitleManager.AddSubtitleStreamFromFile(
            subtitlePath, subtitleName
        )
    }

    func startAudioQueue() {
        let aq = self.createAudioQueue()
        self.setAudioQueue(aq!)
    }

    func getAudioStreamNames() -> [String] {
        var result = [String]()
        for k in aStreamNameIndex.keys {
            result.append(k)
        }
        return result
    }

    func setAudioStreamByName(_ name: String) {
        guard let index = aStreamNameIndex[name] else {
            return
        }
        openAudioCodecWithStream(Int(index))
        audioStream = Int32(index)
        seekCurrent()
    }

    func openAudioCodecWithStream(_ index: Int) {
        aCodecCtx = avcodec_alloc_context3(aCodec)
        let params: UnsafeMutablePointer<AVCodecParameters>! = pFormatCtx!.pointee.streams[index]!.pointee.codecpar

        aStream = pFormatCtx!.pointee.streams[Int(index)]
        aCodecCtx!.pointee.pkt_timebase = aStream!.pointee.time_base
        var ret = avcodec_parameters_to_context(aCodecCtx, params)
        if isErr(ret, "parameters_to_context") {

        }

        var codec_opts: UnsafeMutablePointer<AVDictionary>? = nil
        av_dict_set(&codec_opts, "threads", "auto", 0);
        if isErr(avcodec_open2(aCodecCtx, aCodec, &codec_opts), "avcode_open2 audio") {
            av_dict_free(&codec_opts)
        }
        av_dict_free(&codec_opts)
    }

    func getSubtitleStreamNames() -> [String] {
        return subtitleManager.getSubtitleStreamNames()
    }

    func setSubtitleStreamByName(_ name: String) {
        if let index = sStreamNameIndex[name] {
            subtitleStream = Int32(index)
        }
        subtitleName = name
    }

    func disableSubtitle() {
        subtitleName = nil
    }

    func getSubtitleDirectory() -> String {
        let videoFileURL = URL(fileURLWithPath: filepath)
        return videoFileURL.deletingPathExtension().path
    }

    func createSubtitleDirectory() {
        let dir = getSubtitleDirectory()
        try! FileManager.default.createDirectory(atPath: dir,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
    }

    func initExternalSubtitles(_ videoFilePath: String) {
        let fileManager = FileManager.default

        let videoFileURL = URL(fileURLWithPath: filepath)
        for subtitleExt in ["srt", "ass"] {
            let subtitleFilepath = videoFileURL.deletingPathExtension().appendingPathExtension(subtitleExt)
            if fileManager.fileExists(atPath: subtitleFilepath.path) {
                os_log("Found external subtitle: %@", type: .info, subtitleFilepath.path)
                subtitleManager.initLibass(width, height)
                subtitleManager.AddSubtitleStreamFromFile(subtitleFilepath.path, subtitleFilepath.lastPathComponent)
            }
        }
    }

    /*
     * Main thread for putting packets decoded from ffmpeg
     */
    func decode_thread() {
        decodeThreadIsStopped = false
        while playStatus != PlayStatus.stopped {
            if playStatus != PlayStatus.pause {
                if (layer.status == AVQueuedSampleBufferRenderingStatus.failed) {
                    print("flush")
                    layer.flush()
                    avcodec_flush_buffers(pCodecCtx)
                }
            }
            if (seekReq) {
                let vTimeBase = vStream!.pointee.time_base
                let pts = MSTopts(seekTsInMSec, vTimeBase)
                let masterClock = getMasterClock()
                var flags: Int32 = 0
                if (pts < MSTopts(masterClock, vTimeBase)) {
                    flags |= AVSEEK_FLAG_BACKWARD
                }
                print("move to \(pts), master \(masterClock)")
                let ret = av_seek_frame(pFormatCtx, videoStream, pts, flags)
                //let ret = avformat_seek_file(pFormatCtx, -1, pts, pts, pts, flags)
                if (ret < 0) {
                    os_log("seeking is failed %d", type: .error, ret)
                }
                os_log("seekingto pts: %d TsInMSec: %d", type: .info, pts, seekTsInMSec)
                seekReq = false
                videoIsEOF = false
                videoQueue.flush()
                avcodec_flush_buffers(pCodecCtx)
                layer.flush()
                audioQueue.flush()
                _ = audioQueue.enqueue(&flushPacket)
                subtitleQueue.flush()
                _ = subtitleQueue.enqueue(&flushPacket)
                if (curSubFrame != nil) {
                    avsubtitle_free(&curSubFrame!)
                    curSubFrame = nil
                }
                if (subtitleName != nil) {
                    subtitleManager.flush(subtitleName!)
                }
            }

            if (videoQueue.count > 100 || audioQueue.count > 100) {
                /*
                os_log("video queue: %d audio queue: %d, subtitle queue: %d", type: .debug,
                       videoQueue.count, audioQueue.count, subtitleQueue.count)
 */
            }

            if ((videoStream == -1 || videoQueue.hasEnough(100)) &&
                (audioStream == -1 || audioQueue.hasEnough(20))) {
                /*
                    if (subtitleName != nil) {
                        if subtitleManager.hasNextSubtitle(
                            subtitleName!, getMasterClock() + subtitleOffset, 10) {
                            print("have enough subtitles")
                            u(100000)
                            continue
                        }
                    } else {
                        usleep(100000)
                        continue
                    }
 */
                //print("have enough frames/packets")
                usleep(100000)
                continue
            }

            var packet = av_packet_alloc()
            let ret = av_read_frame(pFormatCtx, packet)
            if (ret == AVERROR_EOF) {
                if (!videoIsEOF) {
                    videoIsEOF = true
                    stop()
                    _ = audioQueue.enqueue(&EOFPacket)
                    av_packet_unref(packet)
                    av_packet_free(&packet)
                }
                os_log("av_read_frame EOF sleep 100ms in case of seeking", type: .info)
                usleep(100000)
                continue
            }
            if (isErr(ret, "av_read_frame")) {
                continue
            }
            //print("queue size \(videoQueue.count) \(audioQueue.count) \(subtitleQueue.count)")

            if (packet?.pointee.stream_index == videoStream) {
                guard let f = decodeVideoFrame(packet) else {
                    av_packet_unref(packet!)
                    av_packet_free(&packet)
                    continue
                }
                _ = videoQueue.enqueue(f)
                av_packet_unref(packet!)
                av_packet_free(&packet)
            } else if (packet?.pointee.stream_index == audioStream) {
                _ = audioQueue.enqueue(packet!)
            } else if (packet?.pointee.stream_index == subtitleStream) {
                _ = subtitleQueue.enqueue(packet!)
            } else {
                //print("may be another stream I didn't take care of")
                av_packet_unref(packet)
                av_packet_free(&packet)
            }
        }
        decodeThreadIsStopped = true
    }

    func seekCurrent() {
        seekReq = true
        seekTsInMSec = getMasterClock()
    }

    func pause() {
        var ret: OSStatus
        ret = AudioQueuePause(_audioQueue!)
        if (isErr(ret, "AudioQueuePause")) {
            
        }
        if (playStatus != PlayStatus.pause) {

            playStatus = PlayStatus.pause

            ret = AudioQueuePause(_audioQueue!)
            if (isErr(ret, "AudioQueuePause")) {

            }

            CMTimebaseSetRate(layer.controlTimebase!, 0)

            _displayTimer?.invalidate()
            os_log("pause", type: .debug)
            //_videoTimer?.invalidate()


        }
    }

    func play() {
        if (playStatus != PlayStatus.playing) {
            playStatus = PlayStatus.playing
            let vRate = vStream!.pointee.avg_frame_rate
            let ti = TimeInterval(Double(vRate.den) / Double(vRate.num))
            os_log("play....", type: .debug)

            CMTimebaseSetRate(layer.controlTimebase!, 1)


            self._displayTimer = Timer.scheduledTimer(withTimeInterval: ti, repeats: true) {_ in
                self.displayViews2()
            }

            /*
             * Since the pause/play causes the video frame move a bit(frame) slow,
             * it has to let audio wait for a bit(frame)
             */
            let ret = AudioQueueStart(self._audioQueue!, nil)
            if (isErr(ret, "AudioQueueStart")) {

            }
        }
    }

    func stop() {
        var ret: OSStatus
        if (playStatus != PlayStatus.stopped) {
            playStatus = PlayStatus.stopped
            //_videoTimer?.invalidate()
            _displayTimer?.invalidate()
            layer.stopRequestingMediaData()
            layer.flushAndRemoveImage()
            ret = AudioQueueStop(_audioQueue!, true)
            _ = isErr(ret, "AudioQueueStop")

            while (decodeThreadIsStopped == false) {
                print("test123 \(decodeThreadIsStopped)")
                // 100ms
                usleep(100000)
            }
        }
    }

    func getStatus() -> PlayStatus {
        return playStatus
    }

    func decodeVideoFrame(_ packet: UnsafeMutablePointer<AVPacket>?)
        -> UnsafeMutablePointer<AVFrame>? {
        var ret: Int32

        if (packet == nil) {
            os_log("no frame avaiable", type: .debug)
            return nil
        }

        repeat {
            ret = avcodec_send_packet(pCodecCtx, packet)
            if (ret == -EAGAIN) {
                print(EAGAIN)
            }
        } while ret == -EAGAIN


        if isErr(ret, "avcodec_send_packet") {
            return nil
        }

        let newFrame = av_frame_alloc()
        ret = avcodec_receive_frame(pCodecCtx, newFrame)
        if (ret == -EAGAIN) {
            print(EAGAIN)
        }
        if isErr(ret, "avcodec_receive_frame") {
            return nil
        }

        if (usingHWAccel && newFrame!.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue) {
            return newFrame
        } else if (usingHWAccel == false) {
            return newFrame
        } else {
            os_log("Something wrong with video format!", type: .fault)
        }
        return newFrame
    }

    func getNextFrame() -> UnsafeMutablePointer<AVFrame>? {
        let frame = videoQueue.dequeue()
        return frame
    }

    func displayViews2() {
        let displayTS = Date().timeIntervalSince1970
        lastDisplayTS = displayTS
        if (lastPara != nil) {
            paraView.attributedText = lastPara
        }
        if (lastAT != nil) {
            subtitleView.attributedText = lastAT
        }
        if (lastPara != nil) {
            sideSubtitleView.attributedText = lastSideSubtitle
        }

        guard let subtitleName = subtitleName else {
            _clearSubtitles()
            return
        }

        guard let subtitles = getSubtitles(subtitleName, getMasterClock() + subtitleOffset) else {
            _clearSubtitles()
            return
        }

        if (subtitles.count == 0) {
            _clearSubtitles()
            return

        }

        var noTag = true
        var tagText = ""
        for sub in subtitles {
            if sub.tag != "" {
                tagText += "\n" + sub.text

                noTag = false
            } else {
                lastPara = NSAttributedString(string: sub.pText,
                                              attributes: paraAttr)

                lastAT = NSAttributedString(string: sub.text,
                                            attributes: subtitleAttr)
            }
        }
        if (noTag) {
            lastSideSubtitle = NSAttributedString(string: "",
                                                  attributes: paraAttr)
        } else {
            lastSideSubtitle = NSAttributedString(string: tagText,
                                                  attributes: paraAttr)
        }
    }

    func _clearSubtitles() {
        lastSideSubtitle = NSAttributedString(string: "",
                                              attributes: paraAttr)

        lastPara = NSAttributedString(string: "",
                                      attributes: paraAttr)

        lastAT = NSAttributedString(string: "",
                                    attributes: subtitleAttr)
    }

    func displayLayer() {
        //let a = Date().timeIntervalSince1970
        let sampleBuffer = getCMSampleBuffer()
        //let b = Date().timeIntervalSince1970
        //os_log("getting sample buffer1 uses %f", type: .debug, b - a)
        if (sampleBuffer == nil) {
            return
        }
        layer.enqueue(sampleBuffer!)
        if (layer.error != nil) {
            os_log("layer fail @%", type: .error, layer.error!.localizedDescription)
        }
    }

    func createPixelBufferPool () -> CVPixelBufferPool? {
        var cpbp: CVPixelBufferPool? = nil
        let sourcePixelBufferOptions: NSDictionary = [
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
            kCVPixelBufferWidthKey: Int(width),
            kCVPixelBufferHeightKey: Int(height),
            kCVPixelBufferPixelFormatTypeKey: CVPIX_FMT
        ]

        let sourcePixelBufferPoolOptions: NSDictionary = [
            kCVPixelBufferPoolMinimumBufferCountKey: 30
        ]

        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            sourcePixelBufferPoolOptions,
            sourcePixelBufferOptions,
            &cpbp)

        if (cpbp == nil) {
            os_log("create pixelBufferPool failed", type: .error)
            return nil
        }
        return cpbp
    }

    func getCMSampleBuffer() -> CMSampleBuffer? {
        //let a = Date().timeIntervalSince1970
        var frame = getNextFrame()
        if (frame == nil) {
            return nil
        }
        //let b = Date().timeIntervalSince1970
        //os_log("getting next frame uses %f", type: .debug, b - a)

        var pixelBuffer : CVPixelBuffer? = nil
        if (usingHWAccel) {
            pixelBuffer = unsafeBitCast(frame!.pointee.buf.0!.pointee.data, to: CVPixelBuffer.self)
        } else {
            if (cvPixelBufferPool == nil) {
                cvPixelBufferPool = createPixelBufferPool()
            }

            let ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
                                                         cvPixelBufferPool!,
                                                         &pixelBuffer)
            if (ret < 0 || pixelBuffer == nil) {
                os_log("create pixelBuffer failed", type: .error)
                return nil
            }
            //let bb = Date().timeIntervalSince1970
            //os_log("getting create pixelBuffer uses %f", type: .debug, bb - b)
            CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags.readOnly)

            let pixelBufferBase = CVPixelBufferGetBaseAddress(pixelBuffer!) //, Int(pFrameRGB!.pointee.linesize.0 * height))
            let cast:UnsafeMutablePointer<UInt8>? = pixelBufferBase!.bindMemory(to: UInt8.self, capacity: 1)

            let r = swsScale(option: sws_ctx,
                           source: frame!,
                           target: pFrameRGB!,
                           height: (pCodecCtx?.pointee.height)!)

            _ = isErr(r, "sws scale")

            //let c = Date().timeIntervalSince1970
            //os_log("getting sws scale uses %f", type: .debug, c - b)

            let size = av_image_get_buffer_size(FMT_CONVERT_TO, width, height, ALIGN)

            let srcFrame = pFrameRGB
            let linesizeCast = withUnsafeMutablePointer(to: &srcFrame!.pointee.linesize.0){$0}
            let targetData = [
                UnsafePointer<UInt8>(srcFrame!.pointee.data.0),
                UnsafePointer<UInt8>(srcFrame!.pointee.data.1),
                UnsafePointer<UInt8>(srcFrame!.pointee.data.2),
                UnsafePointer<UInt8>(srcFrame!.pointee.data.3),
                UnsafePointer<UInt8>(srcFrame!.pointee.data.4),
                UnsafePointer<UInt8>(srcFrame!.pointee.data.5),
                UnsafePointer<UInt8>(srcFrame!.pointee.data.6),
                UnsafePointer<UInt8>(srcFrame!.pointee.data.7),
                ]

            av_image_copy_to_buffer(cast, size, targetData, linesizeCast, FMT_CONVERT_TO, width, height, ALIGN)

            CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags.readOnly)

            //let d = Date().timeIntervalSince1970
            //os_log("getting copy memory uses %f", type: .debug, d - c)
        }

        var info = CMSampleTimingInfo()
        guard let timeBase = vStream?.pointee.time_base else {
            os_log("it should not happen, timebase is nil")
            return nil
        }
        info.presentationTimeStamp = CMTimeMake(
            frame!.pointee.best_effort_timestamp * Int64(timeBase.num), timeBase.den)

        info.duration = kCMTimeInvalid
        info.decodeTimeStamp = kCMTimeInvalid

        // Actually it frees too early for hwaccel, but it didn't zero it
        av_frame_free(&frame)

        var formatDesc: CMFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer!, &formatDesc)

        var sampleBuffer: CMSampleBuffer? = nil

        CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                 pixelBuffer!,
                                                 formatDesc!,
                                                 &info,
                                                 &sampleBuffer);

        //let e = Date().timeIntervalSince1970
        //os_log("getting sws scale uses %f", type: .debug, e - a)
        /*
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer!, true)
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments!, 0), to: CFMutableDictionary.self)
        let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
        let value = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        CFDictionarySetValue(dict, key, value)
 */

        return sampleBuffer!
    }

    func displayViews() {
        let displayTS = Date().timeIntervalSince1970
        //print("image time interval \(displayTS - lastDisplayTS)")
        lastDisplayTS = displayTS
        if (lastImage != nil) {
            displayView.image = lastImage
        }
        if (lastAT != nil) {
            subtitleView.attributedText = lastAT
        }
        if (lastPara != nil) {
            paraView.attributedText = lastPara
        }
    }

    func getBufferAudioTime (_ frame: UnsafeMutablePointer<AVFrame>) -> Int {
        let frameTimeInMs = frame.pointee.nb_samples * 1000 / frame.pointee.sample_rate
        let bufferTime = (audioQueueNum - 1) * audioFramePerQueue * Int(frameTimeInMs)
        return bufferTime
    }

    func ptsToMS(_ pts: Int64, _ timeBase: AVRational) -> Int64 {
        return pts * Int64(timeBase.num) * 1000 / Int64(timeBase.den)
    }

    func MSTopts(_ ms: Int64, _ timeBase: AVRational) -> Int64 {
        return ms * Int64(timeBase.den) / Int64(1000 * timeBase.num)
    }

    func syncAudio(_ frame: UnsafeMutablePointer<AVFrame>) -> Int32 {
        let wantedSamples: Int32 = frame.pointee.nb_samples

        let bufferTime = Int64(getBufferAudioTime(frame))
        // 64 is time for running out buffer
        let ptsInMS = ptsToMS(frame.pointee.best_effort_timestamp, aStream!.pointee.time_base)
        aCurPts = ptsInMS - bufferTime

        let masterClock = getMasterClock()
        let timebase = CMTimebaseGetTime(layer.controlTimebase!)
        let layerTimeInMS = timebase.value * 1000 / Int64(timebase.timescale)
        if (abs(layerTimeInMS - masterClock) > 200) {
            var direct: String
            if (layerTimeInMS > masterClock) {
                direct = "forward"
            } else {
                direct = "backward"
            }
            os_log("reajust master clock %@ from %d to %d", type: .debug, direct, layerTimeInMS, masterClock)
            CMTimebaseSetTime(layer.controlTimebase!, CMTimeMake(masterClock, 1000))
        }

        //print("audio sync \(masterClock)")
        let deltaPts = ptsInMS - bufferTime - masterClock

        let diff = (deltaPts / 3)
        let ptsPerFrame = frame.pointee.nb_samples * 1000 / frame.pointee.sample_rate
        let co = Float(diff) / Float(ptsPerFrame)
        if (deltaPts > 200) {
            if (co < 0.1 && co > -0.1) {
                return wantedSamples + Int32(Float(wantedSamples) * co)
            }
            return wantedSamples + wantedSamples / 15
        } else if (deltaPts < -100) {
            if (co < 0.1 && co > -0.1) {
                return wantedSamples + Int32(Float(wantedSamples) * co)
            }
            return wantedSamples - wantedSamples / 15
        }
        return wantedSamples
    }

    // return in milliseconds
    func getMasterClock() -> Int64 {
        return aCurPts
    }

    func syncVideoClock(_ pts: Int64) -> Int32 {
        //print("\(pts) \(getMasterClock())")
        if (pts < 0) {
            return 0
        }
        let vRate = self.vStream!.pointee.avg_frame_rate
        let ptsPerFrame = Double(vRate.den) / Double(vRate.num) * 1000
        let delta = pts - getMasterClock()
        vCurPts = pts
        return Int32(Double(delta) / ptsPerFrame)
    }

    func isSubOntime(_ sub: AVSubtitle) -> Bool {
        if ((sub.pts / 1000 + Int64(sub.end_display_time)) > vCurPts) {
            return true
        }
        return false
    }

    func decodeSubtitle2() -> AVSubtitle? {
        var packet = subtitleQueue.dequeue()
        if (packet == nil) {
            return nil
        }

        if (packet == &flushPacket) {
            ass_flush_events(assTrack)
            avcodec_flush_buffers(sCodecCtx)
            return nil
        }

        var subframe = AVSubtitle()
        var got_sub: Int32 = 0
        var ret: Int32


        ret = avcodec_decode_subtitle2(sCodecCtx, &subframe, &got_sub, packet)
        if (isErr(ret, "avcodec_decode_subtitle2")) {
            return nil
        }

        av_packet_unref(packet!)
        av_packet_free(&packet)

        return subframe
    }

    func getSubFrameText(_ subframe: AVSubtitle) -> String {
        var text = ""
        let num = subframe.num_rects
        // It's an invalid subtitle frame
        if (num < 1) {
            return ""
        }
        for i in 0...num - 1 {
            let r = subframe.rects[Int(i)]!.pointee
            if (r.ass == nil) {
                continue
            }
            guard let track = assTrack?.pointee else {
                continue
            }
            let start_time = subframe.pts / 1000
            let duration = subframe.end_display_time
            let n_events = track.n_events
            ass_process_chunk(assTrack, r.ass,
                              Int32(strlen(r.ass)),
                              start_time, Int64(duration))

            if n_events == assTrack!.pointee.n_events {
                let assLine = String.init(cString: r.ass)
                print("failed to process ass line \(assLine)")

            }
            let eventIndex = assTrack!.pointee.n_events - 1
            let event = assTrack!.pointee.events[Int(eventIndex)]
            if (event.Text == nil) {
                continue
            }
            text += String.init(cString: event.Text)
        }
        return text
    }

    func getSubtitles(_ subtitleName: String?, _ pts: Int64) -> [Subtitle]? {
        if (subtitleName == nil) {
            return nil
        }

        let subtitles = subtitleManager.getSubtitles(subtitleName!, pts)
        if (subtitles != nil && subtitles!.count != 0) {
            return subtitles
        }

        if (subtitleName?.hasPrefix("builtin") == false) {
            return nil
        }

        var text: String = ""
        var subframe = decodeSubtitle2()
        if (subframe == nil) {
            return nil
        }
        text = getSubFrameText(subframe!)

        if (curSubFrame != nil) {
            avsubtitle_free(&curSubFrame!)
        }

        let plainText = renderAssLine(text)

        let para = mdict?.processLine(plainText)

        var pText = ""
        if (para != nil) {
            for (k, v) in para! {
                pText += "\(k): \(v)\n"
            }
        }

        subtitleManager.addSubtitle(
            subtitleName!,
            plainText,
            pText,
            subframe!.pts / 1000,
            Int64(subframe!.end_display_time))

        avsubtitle_free(&subframe!)
        return subtitleManager.getSubtitles(subtitleName!, pts)
    }

    func decodeSubtitle() -> [UnsafeMutablePointer<ASS_Image>] {
        var imgArray = [UnsafeMutablePointer<ASS_Image>]()
        if (curSubFrame != nil) {
            if (curSubFrame!.pts / 1000000 > vCurPts) {
                /* Got a subtitle ahead */
                return imgArray
            } else if (isSubOntime(curSubFrame!)) {
                return curSubImgArray
            }
        }
        var packet = subtitleQueue.dequeue()
        if (packet == nil) {
            return imgArray
        }

        if (packet == &flushPacket) {
            ass_flush_events(assTrack)
            avcodec_flush_buffers(sCodecCtx)
            return imgArray
        }

        var subframe = AVSubtitle()
        var got_sub: Int32 = 0
        var ret: Int32


        ret = avcodec_decode_subtitle2(sCodecCtx, &subframe, &got_sub, packet)
        if (isErr(ret, "avcodec_decode_subtitle2")) {
            return imgArray
        }

        av_packet_unref(packet!)
        av_packet_free(&packet)

        let num = subframe.num_rects

        for i in 0...num - 1 {
            let r = subframe.rects[Int(i)]!.pointee
            if (r.ass == nil) {
                continue
            }
            let assLine = String.init(cString: r.ass)
            let now = subframe.pts / 1000 + Int64(subframe.end_display_time / 2)
            //let duration = subframe.end_display_time
            //ass_process_chunk(assTrack, r.ass, Int32(assLine.count), subframe.pts / 1000, Int64(duration))
            ass_process_data(assTrack, r.ass, Int32(assLine.count))
            let a = assTrack?.pointee
            let eventIndex = a!.n_events - 1
            let b = a?.events[Int(eventIndex)]
            let c = String.init(cString: b!.Text)
            subtitleView.text = c
            //let now = Int64(Double(subframe.pts) * av_q2d(sCodecCtx!.pointee.time_base) * 1000.0)
            let img = ass_render_frame(assRenderer,
                                   assTrack,
                                   now,
                                   nil)
            if (img == nil) {
                print("no img was got")
                return imgArray
            }

            if (img!.pointee.dst_y + img!.pointee.h > height) {
                img!.pointee.dst_y = height - img!.pointee.h;
            }
            if (img!.pointee.dst_x + img!.pointee.w > width) {
                img!.pointee.dst_x = width - img!.pointee.w;
            }
            imgArray.append(img!)
        }
        if (curSubFrame != nil) {
            avsubtitle_free(&curSubFrame!)
        }
        curSubFrame = subframe
        curSubImgArray = imgArray
        if (curSubFrame!.pts / 1000 > videoPts) {
            /* Got a subtitle ahead */
            return [UnsafeMutablePointer<ASS_Image>]()
        } else if (isSubOntime(curSubFrame!)) {
            return curSubImgArray
        }
        return [UnsafeMutablePointer<ASS_Image>]()
    }

    func decode_audio() -> UnsafeMutablePointer<AVFrame>? {
        var ret: Int32

        //os_log("decode_audio", type: .debug)
        var packet = audioQueue.dequeue()
        if (packet == nil) {
            print("decode_audio is nil")
            return nil
        }
        let frame = av_frame_alloc()

        if (packet == &flushPacket) {
            avcodec_flush_buffers(aCodecCtx)
            return nil
        } else if (packet == &EOFPacket) {
            stop()
            return nil
        }

        repeat {
            ret = avcodec_send_packet(aCodecCtx, packet!)
            if (ret == -EAGAIN) {
                print(EAGAIN)
            }
        } while ret == -EAGAIN

        if isErr(ret, "avcodec_send_packet") {
            return nil
        }

        av_packet_unref(packet!)
        av_packet_free(&packet)

        ret = avcodec_receive_frame(aCodecCtx, frame)
        if (ret == -EAGAIN) {
            print(EAGAIN)
        }
        if isErr(ret, "avcodec_receive_frame") {
            return nil
        }
        let dataSize = av_samples_get_buffer_size(nil,
                                                  aCodecCtx!.pointee.channels,
                                                  frame!.pointee.nb_samples,
                                                  aCodecCtx!.pointee.sample_fmt,
                                                  1)


        if (dataSize < 0) {
            print("This shouldn't occur")
            return nil
        }
        return frame
    }

    func setAudioQueue(_ aq: AudioQueueRef) {
        _audioQueue = aq
    }

    func getMoviePosition() -> Int64 {
        return getMasterClock()
    }

    func getMovieDuration() -> Int64 {
        return duration
    }

    func getMoviePositionInPercent() -> Int {
        return Int(getMasterClock() * Int64(100) / getMovieDuration())
    }

    func createAudioQueue() -> AudioQueueRef? {
        var outputQueue: AudioQueueRef? = nil

        var status: OSStatus = 0
        let videoRef = UnsafeMutablePointer<Video>.allocate(capacity: 1)
        videoRef.initialize(to: self)
        var ASDesc = AudioStreamBasicDescription()
        setAudioDesc(&ASDesc, self)

        status = AudioQueueNewOutput(&ASDesc, callback, videoRef,
                                     nil, CFRunLoopMode.commonModes.rawValue,
                                     0, &outputQueue)

        if (outputQueue == nil) {
            print("failed to create output created")
            print("status")
        }


        let bufferSize = UInt32(1024 * 256 * 2)
        for _ in 0..<self.audioQueueNum {
            var bufferRef: AudioQueueBufferRef? = AudioQueueBufferRef.allocate(capacity: 1)
            status = AudioQueueAllocateBuffer(outputQueue!, bufferSize, &bufferRef)
            bufferRef?.pointee.mAudioDataByteSize = 0
            callback(videoRef, outputQueue!, bufferRef!)
            if (status != 0) {
                print("enqueue fail")
            }
        }

        //assert(noErr == status)
        AudioQueueSetParameter(outputQueue!, kAudioQueueParam_Volume, 1.0);
        //status = AudioQueueAddPropertyListener(outputQueue, 1, KKAudioQueueRunningListener, selfPointer)
        status = AudioQueuePrime(outputQueue!, 0, nil)
        print(status.description)
        status = AudioQueueStart(outputQueue!, nil)
        print(status.description)
        return outputQueue
    }
    /*
     * Video related initials
     */
    func vDecInit() -> Int32 {
        var ret: Int32
        // get first video stream to find codec
        videoStream = av_find_best_stream(pFormatCtx,
                                          AVMEDIA_TYPE_VIDEO,
                                          -1, -1, &pCodec, 0)
        if isErr(videoStream, "av_find_best_stream video") {
            return -1
        }

        if (pCodec == nil) {
            print("Unsupport codec\n")
            return -1
        }

        vStream = pFormatCtx?.pointee.streams[Int(videoStream)]
        let params: UnsafeMutablePointer<AVCodecParameters>! = pFormatCtx!.pointee.streams[Int(videoStream)]!.pointee.codecpar
        //params.pointee.format = FMT_CONVERT_TO.rawValue

        pCodecCtx = avcodec_alloc_context3(pCodec)
        pCodecCtx!.pointee.pkt_timebase = vStream!.pointee.time_base
        ret = avcodec_parameters_to_context(pCodecCtx, params)
        if isErr(ret, "parameters_to_context") {
            return ret
        }

        if (!CODEC_HWAccel.contains(pCodecCtx!.pointee.codec_id)) {
            /*
             * "divx style packed b frames" troubles videotoolbox,
             * though not all Divx got packed b frames, we don't
             * have exposed api to detect that, so we forbid all
             */
            usingHWAccel = false
        }
        // hw decode accelator
        if (usingHWAccel) {
            var hwDeviceCtx: UnsafeMutablePointer<AVBufferRef>? = nil
            ret = av_hwdevice_ctx_create(&hwDeviceCtx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0)
            if isErr(ret, "av_hwdevice_ctx_create") {

            }
            pCodecCtx!.pointee.hw_device_ctx = av_buffer_ref(hwDeviceCtx)

            pCodecCtx!.pointee.get_format = get_format
            av_opt_set_int(pCodecCtx, "refcounted_frames", 1, 0)
        }
        var codec_opts: UnsafeMutablePointer<AVDictionary>? = nil
        av_dict_set(&codec_opts, "threads", "auto", 0);
        if isErr(avcodec_open2(pCodecCtx, pCodec, &codec_opts), "avcodec_open2 video") {
            av_dict_free(&codec_opts)
            return ret
        }
        av_dict_free(&codec_opts)

        width = params.pointee.width
        height = params.pointee.height
        swFrame = av_frame_alloc()
        // Frame for converting from original frame
        pFrameRGB = av_frame_alloc()

        let pix_fmt = AVPixelFormat(rawValue: params.pointee.format)

        /*
        sws_ctx = sws_getContext(width, height, pix_fmt,
                                 width, height, AV_PIX_FMT_RGB24,
                                 SWS_BILINEAR, nil, nil, nil)
 */

        if (usingHWAccel) {
            sws_ctx = sws_getContext(width, height, AV_PIX_FMT_NV12,
                                 width, height, FMT_CONVERT_TO,
                                 SWS_BILINEAR, nil, nil, nil)
        } else {
            sws_ctx = sws_getContext(width, height, pix_fmt,
                                     width, height, FMT_CONVERT_TO,
                                     SWS_BILINEAR, nil, nil, nil)
        }

        if (sws_ctx == nil){
            os_log("sws_ctx is nil", type: .error)
            return -1
        }

        let linesizePointer = withUnsafeMutablePointer(to: &pFrameRGB!.pointee.linesize.0){$0}
        let datasizePointer = withUnsafeMutablePointer(to: &pFrameRGB!.pointee.data.0){$0}

        ret = av_image_alloc(datasizePointer,
                             linesizePointer,
                             width, height,
                             FMT_CONVERT_TO, ALIGN)

        if (isErr(ret, "avImageFillArrays")) {
            return ret
        }
        return 0
    }

    /*
     * Audio related initials
     */
    func aDecInit() -> Int32{
        audioStream = av_find_best_stream(pFormatCtx,
                                          AVMEDIA_TYPE_AUDIO,
                                          -1, -1,
                                          &aCodec,
                                          0)

        if isErr(audioStream, "av_find_best_stream audio") {
            return -1
        }

        if (aCodec == nil) {
            print("Unsupport codec\n")
            return -1
        }

        for i in 0..<pFormatCtx!.pointee.nb_streams {
            let stream = pFormatCtx!.pointee.streams![Int(i)]!
            let par = stream.pointee.codecpar
            if (par!.pointee.codec_type == AVMEDIA_TYPE_AUDIO) {
                var lang = getAVOpt(stream, "language")
                if (lang == nil) {
                    lang = "unknown"
                }
                var title = getAVOpt(stream, "title")
                if (title == nil) {
                    title = "noname"
                }

                let streamName = "\(title!) [\(lang!)]"
                aStreamNameIndex[streamName] = i
            }
        }
        openAudioCodecWithStream(Int(audioStream))

        return 0
    }

    func deinit0() {
        avformat_close_input(&pFormatCtx)
        avformat_free_context(pFormatCtx)
        print("free")

        avcodec_free_context(&pCodecCtx)
        avcodec_free_context(&aCodecCtx)
        avcodec_free_context(&sCodecCtx)


        if (pFrameRGB != nil) {
            av_free(pFrameRGB?.pointee.data.0)
            av_frame_unref(pFrameRGB)
            av_frame_free(&pFrameRGB)
        }

        if (sws_ctx != nil) {
            sws_freeContext(sws_ctx)
        }

        if (swrCtx != nil) {
            swr_free(&swrCtx)
        }

        videoQueue.flush()
        audioQueue.flush()

        if (subtitleStream != -1) {
            subtitleQueue.flush()

            if (curSubFrame != nil) {
                avsubtitle_free(&curSubFrame!)
                curSubFrame = nil
            }

            ass_flush_events(assTrack)
            ass_free_track(assTrack)
            ass_renderer_done(assRenderer)
            ass_library_done(assLibrary)
        }
    }
    /*
     * Subtitle related initials
     */
    func sDecInit() -> Int32 {
        subtitleStream = av_find_best_stream(pFormatCtx,
                                             AVMEDIA_TYPE_SUBTITLE,
                                             -1, -1, &sCodec, 0)
        if (subtitleStream < 0) {
            os_log("No subtitle was found", type: .info)
            subtitleStream = -1
            return -1
        }
        //var codec_opts: UnsafeMutablePointer<AVDictionary>? = UnsafeMutablePointer<AVDictionary>.allocate(capacity: 1)
        //var codec_opts: AVDictionary = AVDictionary()
        //var b: UnsafeMutablePointer<AVDictionary>? = withUnsafeMutablePointer(to: &codec_opts){$0}
        ////av_dict_set(&b, "sub_text_format", "ass", AV_DICT_DONT_OVERWRITE);
        ////av_dict_set(&b, "sub_text_format", "ass", 0);

        assInit(width, height)
        sCodecCtx = avcodec_alloc_context3(sCodec)
        for i in 0..<pFormatCtx!.pointee.nb_streams {
            let stream = pFormatCtx!.pointee.streams![Int(i)]!
            guard let par = stream.pointee.codecpar else {
                continue
            }
            if (par.pointee.codec_type == AVMEDIA_TYPE_SUBTITLE) {
                let subtitle_header_cast = unsafeBitCast(par.pointee.extradata,
                                                         to: UnsafeMutablePointer<Int8>.self)
                ass_process_data(assTrack,
                                 subtitle_header_cast,
                                 par.pointee.extradata_size)
                let sSt = pFormatCtx?.pointee.streams[Int(i)]
                sCodecCtx?.pointee.pkt_timebase = sSt!.pointee.time_base
                var lang = getAVOpt(sSt!, "language")
                if (lang == nil) {
                    lang = "unknown"
                }

                var title = getAVOpt(sSt!, "title")
                if (title == nil) {
                    title = "noname"
                }

                let subtitleName = "builtin-\(title!) [\(lang!)]"
                sStreamNameIndex[subtitleName] = i
                subtitleManager.AddSubtitleStream(subtitleName)
            }
        }


        //sCodecCtx?.pointee.pkt_timebase = sSt!.pointee.time_base
        //let tb = sSt!.pointee.time_base
        var codec_opts: UnsafeMutablePointer<AVDictionary>? = nil
        av_dict_set(&codec_opts, "threads", "auto", 0);
        av_dict_set(&codec_opts, "sub_text_format", "ass", 0);
        if isErr(avcodec_open2(sCodecCtx,
                               sCodec,
                               &codec_opts),
                 "avcode_open2 subtitle") {
            av_dict_free(&codec_opts)
            return -1
        }
        av_dict_free(&codec_opts)

        let subtitle_header = String.init(cString: sCodecCtx!.pointee.subtitle_header)
        if (subtitle_header != "") {
            let subtitle_header_cast = unsafeBitCast(sCodecCtx?.pointee.subtitle_header,
                                                     to: UnsafeMutablePointer<Int8>.self)

            ass_process_data(assTrack,
                             subtitle_header_cast,
                             sCodecCtx!.pointee.subtitle_header_size)
        }

        ass_set_check_readorder(assTrack, 1)
        return 0
    }

    func assInit(_ width: Int32, _ height: Int32) {
        assLibrary = ass_library_init()
        if (assLibrary == nil) {
            print("ass_library_init failed!")
            return
        }
        ass_set_message_cb(assLibrary, nil, nil)
        assRenderer = ass_renderer_init(assLibrary)
        assTrack = ass_new_track(assLibrary)
        ass_set_frame_size(assRenderer, width, height)
        ass_set_fonts(assRenderer, nil, "Sans", 1, nil, 1)
        //ass_set_fonts(assRenderer, nil, "Serif", 1, nil, 1)
        ff_draw_init(&draw, AV_PIX_FMT_YUV420P, 0)
    }

    /*
    func genNextImage() {
        var ret: Int32

        let frame = getNextFrame()
        if (frame == nil) {
            return
        }

        lastVideoPTS = frame!.pointee.best_effort_timestamp
        _ = syncVideoClock(lastVideoPTS)

        let subtitles = getSubtitles(subtitleName, frame!.pointee.best_effort_timestamp)

        ret = swsScale(option: sws_ctx,
                       source: frame!,
                       target: pFrameRGB!,
                       height: (pCodecCtx?.pointee.height)!)


        av_frame_unref(frame)

        if isErr(ret, "swsScale") {
        }

        let linesize = pFrameRGB?.pointee.linesize.0 ?? 0

        let data = CFDataCreate(kCFAllocatorDefault,
                                pFrameRGB?.pointee.data.0,
                                CFIndex(linesize * height)
        )
        if (data == nil) {
            print("data is nil\n")
        }
        let n = CGDataProvider(data: data!)
        if (n == nil) {
            print("n is nil\n")
        }


        let cgImage = CGImage(width: Int(width), height: Int(height),
                              bitsPerComponent: 8, bitsPerPixel: 24,
                              bytesPerRow: Int(linesize),
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: 0),
                              provider: n!,
                              decode: nil, shouldInterpolate: false,
                              intent: .defaultIntent)

        if (cgImage == nil) {
            print("cgImage is nil\n")
        }

        var subText = ""
        var subPText = ""
        if (subtitle != nil) {
            subText = subtitle!.text
            subPText = subtitle!.pText
        }


        lastAT = NSAttributedString(string: subText,
                                    attributes: subtitleAttr)

        lastImage = UIImage(cgImage: cgImage!)
        lastPara = NSAttributedString(string: subPText,
                                      attributes: paraAttr)

    }*/
}


func callback (_ clientData: UnsafeMutableRawPointer?, _ AQ: OpaquePointer, _ buffer: AudioQueueBufferRef) {
    var ret: Int32
    guard let videoRef = clientData?.bindMemory(to: Video.self, capacity: 1) else {
        return
    }
    let cast:UnsafeMutablePointer<UInt8>? = buffer.pointee.mAudioData.bindMemory(to: UInt8.self, capacity: 1)

    buffer.pointee.mAudioDataByteSize = 0
    buffer.pointee.mPacketDescriptionCount = 0
    //let dataSize = Int(av_get_bytes_per_sample(videoRef.pointee.aCodecCtx!.pointee.sample_fmt))
    let dataSize = av_get_bytes_per_sample(AUDIO_FMT_CONVERT_TO)
    var offset = 0
    var pFrame: UnsafeMutablePointer<AVFrame>?

    var frameCount = 0
    while (true) {
        if (frameCount == videoRef.pointee.audioFramePerQueue) {
            break
        }
        var cast2 = cast?.advanced(by: offset)
        let cast1 = withUnsafeMutablePointer(to: &cast2){$0}
        repeat {
            pFrame = videoRef.pointee.decode_audio()
            if (pFrame == nil) {
                os_log("audio queue is empty", type: .debug)
                if (videoRef.pointee.playStatus == PlayStatus.stopped) {
                    return
                }
                usleep(100000)
            }
        } while (pFrame == nil)
        let channels:Int32 = 2
        let sampleNum: Int = Int(pFrame!.pointee.nb_samples)
        if (pFrame != nil) {
            /*
             if (buffer.pointee.mAudioDataBytesCapacity - buffer.pointee.mAudioDataByteSize < dataSize * sampleNum) {
                break
             }
 */
            let inBuffers = unsafeBitCast(pFrame?.pointee.extended_data,
                                          to: UnsafeMutablePointer<UnsafePointer<UInt8>?>.self)

            let wantedSamples = videoRef.pointee.syncAudio(pFrame!)

            let diff = wantedSamples.advanced(by: -sampleNum)

            /*
            var newSwrCtx = false
            var swrCtx: OpaquePointer?
            if (pFrame?.pointee.channels != videoRef.pointee.aCodecCtx?.pointee.channels) {
                newSwrCtx = true
                swrCtx = videoRef.pointee.getSwrByFrame(pFrame!)
            } else {
                swrCtx = videoRef.pointee.swrCtx
            }
            let aa = videoRef.pointee.aCodecCtx?.pointee
            let bb = pFrame?.pointee

            swrCtx = swr_alloc_set_opts(
                nil,
                //av_get_default_channel_layout(aCodecCtx!.pointee.channels),
                Int64(av_get_channel_layout("stereo")),
                AUDIO_FMT_CONVERT_TO,
                videoRef.pointee.aCodecCtx!.pointee.sample_rate,
                av_get_default_channel_layout(videoRef.pointee.aCodecCtx!.pointee.channels),
                videoRef.pointee.aCodecCtx!.pointee.sample_fmt,
                videoRef.pointee.aCodecCtx!.pointee.sample_rate,
                0,
                nil)
            swr_init(swrCtx)
            */
            videoRef.pointee.tryReinitSwrCtxByFrame(pFrame!)

            ret = swr_set_compensation(videoRef.pointee.swrCtx,
                                       diff,
                                       wantedSamples)

            if isErr(ret, "swrCtxComp set compensation") {
                return
            }
            // swrCtx is aware of the channels,
            // so it doesn't need to multiply channels here
            let actualSamples = swr_convert(videoRef.pointee.swrCtx,
                                            cast1,
                                            wantedSamples,
                                            inBuffers,
                                            pFrame!.pointee.nb_samples)

            /*
            if (newSwrCtx) {
                swr_free(&swrCtx)
            }
 */
            if (actualSamples != pFrame!.pointee.nb_samples) {
                os_log("actualSamples %d", type: .debug, actualSamples)
            }
            /*
            ret = swr_set_compensation(videoRef.pointee.swrCtx,
                                       0,
                                       Int32(sampleNum))
 */

            offset += Int(dataSize * Int32(sampleNum) * channels)
            buffer.pointee.mAudioDataByteSize += UInt32(Int32(dataSize) * actualSamples * channels)

            /* TODO: it may lead to leak if AudioQueue was stopped before callback run here */

            av_frame_unref(pFrame)
            av_frame_free(&pFrame)
            frameCount += 1
        } else {
            break
        }
    }
    ret = AudioQueueEnqueueBuffer(AQ, buffer, 0, nil)
    if (ret != 0) {
        print("enqueue fail")
    }
}

