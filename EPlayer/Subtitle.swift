//
//  Subtitle.swift
//  EPlayer
//
//  Created by 林守磊 on 04/04/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import os.log
import Foundation

class SubtitleManager {
    var subtitleStreams = [String: SubtitleStream]()
    //var subtitles = [Int64: Subtitle]()
    var assLibrary : AssLibrary?
    var assRenderer: AssRenderer?
    var mdict: EPDictionary?
    var libassInited = false
    init() {

    }

    func initLibass (_ width: Int32, _ height: Int32) {
        if (libassInited) {
            return
        }

        if (assLibrary == nil) {
            assLibrary = ass_library_init()
            if (assLibrary == nil) {
                os_log("ass_library_init failed", type: .error)
                return
            }

        }

        if (assRenderer == nil) {
            assRenderer = ass_renderer_init(assLibrary)
            if (assRenderer == nil) {
                os_log("ass_renderer_init failed", type: .error)
                return
            }
        }

        ass_set_frame_size(assRenderer, width, height)
        ass_set_fonts(assRenderer, nil, "Sans", 1, nil, 1)

        libassInited = true
    }

    func addSubtitle(_ subtitleName: String,
                     _ text: String,
                     _ pText: String,
                     _ pts: Int64,
                     _ duration: Int64) {
        if (subtitleStreams[subtitleName] == nil) {
            return
        }

        let stream = subtitleStreams[subtitleName]!
        stream.addSubtitle(text, pText, pts, duration)
    }

    func addSubtitlesWithFile(_ filepath: String) {

    }

    func flush(_ subtitleName: String) {
        let stream = subtitleStreams[subtitleName]
        if (stream != nil) {
            stream!.flush()
        }
    }

    func getSubtitles(_ subtitleName: String, _ pts: Int64) -> [Subtitle]? {
        let stream = subtitleStreams[subtitleName]
        if (stream == nil) {
            return nil
        }

        return stream!.getSubtitleByPTS(pts)
    }

    func AddSubtitleStream(_ subtitleName: String) {
        let stream = SubtitleStream(subtitleName, dict: mdict)
        subtitleStreams[subtitleName] = stream
    }

    func AddSubtitleStreamFromFile(_ filepath: String, _ subtitleName: String) {
        var stream: SubtitleStream?
        if filepath.hasSuffix("ass") || filepath.hasSuffix("ssa") {
            stream = SubtitleStream(subtitleName, filepath, assLibrary!, assRenderer!, dict: mdict)
        } else {
            stream = SubtitleStream(subtitleName, filepath, dict: mdict)
        }
        if (stream != nil) {
            subtitleStreams[subtitleName] = stream
        }
    }

    func getSubtitleStreamNames() -> [String] {
        var ret = [String]()
        for (k, _) in subtitleStreams {
            ret.append(k)
        }
        return ret
    }

    func hasNextSubtitle(_ subtitleName: String, _ pts: Int64, _ num: Int) -> Bool {
        guard let stream = subtitleStreams[subtitleName] else {
            return true
        }

        return stream.hasNextSubtitle(pts, num)
    }
}


class SubtitleStream {
    var subtitleName: String
    var subtitles = [Int64: [Subtitle]]()
    var lastSubtitles: [Subtitle]?
    var assTrack: UnsafeMutablePointer<ASS_Track>?
    var assLibrary : AssLibrary?
    var assRenderer: AssRenderer?
    var usingLibass = false
    var mdict: EPDictionary?

    init (_ name: String, dict: EPDictionary?) {
        subtitleName = name
        mdict = dict
    }

    init? (_ name: String, _ filepath: String, dict: EPDictionary?) {
        /* supposed to be subrip */

        subtitleName = name
        mdict = dict
        guard let subRip = Subrip(filepath: filepath) else { return nil }
        for e in subRip.events {
            let pts = e.pts

            if (mdict == nil) {
                self._addSubtitleEvent(pts, Subtitle(e.text, "", pts, e.duration, e.tag))
            } else {
                _addSubtitleEvent(pts, Subtitle(e.text, process(mdict!, e.text), pts, e.duration, e.tag))
            }
        }
    }

    init? (_ name: String, _ filepath: String, _ assLibrary: AssLibrary, _ assRenderer: AssRenderer, dict: EPDictionary?) {
        subtitleName = name
        self.assLibrary = assLibrary
        self.assRenderer = assRenderer
        filepath.withCString { s in
            assTrack = ass_read_file(assLibrary, UnsafeMutablePointer(mutating: s), nil)
        }

        guard let assTrack = assTrack else { return nil }
        mdict = dict

        for i in 0..<assTrack.pointee.n_events {
            let event = assTrack.pointee.events[Int(i)]
            let pts = event.Start
            let duration = event.Duration
            let rawAssText = String.init(cString: event.Text)
            let text = renderAssLine(rawAssText)
            var pText = ""
            var tag = getAssTag(rawAssText)
            if (tag == "\\p") {
                continue
            }
            if (event.MarginL != 0 || event.MarginR != 0 || event.MarginV != 0) {
                tag = "custom"
            }
            if (mdict != nil) {
                pText = process(mdict!, text)
            }
            self._addSubtitleEvent(pts, Subtitle(text, pText, pts, duration, tag))
        }
        usingLibass = true
    }

    func getSubtitleByPTS(_ pts: Int64) -> [Subtitle]? {
        if (subtitles[pts] != nil) {
            return subtitles[pts]!
        }

        var retSubs = [Subtitle]()
        var retLastSubs = [Subtitle]()

        if (lastSubtitles != nil && lastSubtitles?.count != 0) {
            var suite = false
            for i in lastSubtitles! {
                if (i.isSuite(pts)) {
                    if (i.tag == "") {
                        suite = true
                    }
                    retLastSubs.append(i)
                }
            }

            if (suite) {
                return retLastSubs
            }
        }

        // if we got a subtitle beforehand, it assumes that
        // would be the next subtitle. It seems unfair, but
        // good for performance. We got to flush subtitle if
        // seeking is happened
        /*
        if (lastSutitle != nil && pts < lastSutitle!.pts) {
            return Subtitle()
        }
 */
        var cache = false
        for (_, subs) in subtitles {
            for sub in subs {
                if (sub.isSuite(pts)) {
                    retSubs.append(sub)
                    if (sub.tag == "") {
                        // only accelerate subtitles of line
                        cache = true
                    }
                }
            }
        }

        if (cache) {
            lastSubtitles = retSubs
        }
        return retSubs
    }

    func addSubtitle(_ text: String,
                     _ pText: String,
                     _ pts: Int64,
                     _ duration: Int64) {
        let s = Subtitle(text, pText, pts, duration)
        self._addSubtitleEvent(pts, s)
        lastSubtitles = [s]
    }

    func flush() {
        lastSubtitles = nil
    }

    func hasNextSubtitle(_ pts: Int64, _ num: Int) -> Bool {
        let sortedSubtitles = subtitles.sorted(by: {$0.key > $1.key})
        let len = sortedSubtitles.count
        var i = 0
        for (subPts, sub) in sortedSubtitles {
            i += 1
            if (subPts > pts && len - i >= num) {
                return true
            } else {
                return false
            }
        }
        return false
    }

    func _addSubtitleEvent(_ pts: Int64, _ subtitle: Subtitle) {
        if (subtitles[pts] == nil) {
            subtitles[pts] = [Subtitle]()
        }
        subtitles[pts]?.append(subtitle)
    }
}

class Subtitle {
    var pts: Int64
    var duration: Int64
    var text: String
    var pText: String
    var tag: String
    var image: ASS_Image?

    init(_ text: String, _ pText: String, _ pts: Int64, _ duration: Int64, _ tag: String = "") {
        self.text = text
        self.pText = pText
        self.pts = pts
        self.duration = duration
        self.tag = tag
    }

    init() {
        self.text = ""
        self.pText = ""
        self.pts = 0
        self.duration = 0
        self.tag = ""
    }

    func isSuite(_ pts: Int64) -> Bool {
        if (self.pts < pts && (self.duration + self.pts) >= pts) {
            return true
        }
        return false
    }
}

func process(_ mdict: EPDictionary, _ text: String) -> String {
    let para = mdict.processLine(text)

    var pText = ""
    for (k, v) in para {
        pText += "\(k): \(v)\n"
    }

    return pText
}

func saveSubtitleToFile(_ subinfo: Subinfo, _ subtitlePath: String) -> Bool {
    guard let data = subinfo.data else {
        return false
    }

    return FileManager.default.createFile(
        atPath: subtitlePath,
        contents: data,
        attributes: nil)
}

func downloadSubtitleAndSave(_ videoFilePath: String, closure: @escaping (_ subtitlePath: String, _ subtitleName: String) -> Void) {
    let MAX_SUBTITLES = 10
    var subtitleID = ["chi": 0,
                      "eng": 0]

    let videoFileURL = URL(fileURLWithPath: videoFilePath)
    let subtitleDirectory = videoFileURL.deletingPathExtension().path

    try! FileManager.default.createDirectory(atPath: subtitleDirectory,
                                             withIntermediateDirectories: true,
                                             attributes: nil)

    for lang in subtitleID.keys {
        OpenSubtitlesAPI().downloadSubtitles(videoFilePath, lang) { (_ subinfo: Subinfo) in
            if (subtitleID[lang]! > MAX_SUBTITLES) {
                return
            }
            let subtitleName = subinfo.langs.joined(separator: "&") + ".\(subtitleID[lang]!)." + subinfo.ext
            let subtitlePath = subtitleDirectory + "/" + subtitleName
            if (saveSubtitleToFile(subinfo, subtitlePath)) {
                subtitleID[lang]! += 1
                closure(subtitlePath, subtitleName)
            }
        }
    }

    for lang in ["chi"] {
        XLAPI().downloadSubtitles(videoFilePath, lang) { (_ subinfo: Subinfo) in
            if (subtitleID[lang]! > MAX_SUBTITLES) {
                return
            }
            let subtitleName = subinfo.langs.joined(separator: "&") + ".\(subtitleID[lang]!)." + subinfo.ext
            let subtitlePath = subtitleDirectory + "/" + subtitleName
            if (saveSubtitleToFile(subinfo, subtitlePath)) {
                subtitleID[lang]! += 1
                closure(subtitlePath, subtitleName)
            }
        }
    }
}
