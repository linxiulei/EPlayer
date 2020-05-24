//
//  utils.swift
//  EPlayer
//
//  Created by 林守磊 on 31/03/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import os.log
import Foundation

class Averager {
    var count: UInt32 = 0
    var total: UInt32 = 0
    var q = [UInt32]()

    init(_ initVal: UInt32, _ count: UInt32) {
        for _ in 0..<count {
            q.append(initVal)
        }
        total = initVal * count
        self.count = count
    }

    func addNum(_ n: UInt32) {
        total -= q.remove(at: 0)
        total += UInt32(n)
        q.append(n)
    }

    func getAvg() -> UInt32 {
        return total / count
    }
}

public struct AVPacketQueue<T> {
    fileprivate var array = [UnsafeMutablePointer<T>]()
    fileprivate var dispatchQueue = DispatchQueue(label: "MyQueue")
    fileprivate var size: Int
    fileprivate var empty_mutex = DispatchSemaphore(value: 1)
    fileprivate var full_mutex = DispatchSemaphore(value: 1)
    fileprivate var mutex = DispatchSemaphore(value: 1)

    init(_ size: Int) {
        self.size = size
    }


    public var isEmpty: Bool {
        return array.isEmpty
    }

    public var isFull: Bool {
        if (size != 0) {
            return array.count >= size
        }
        return false
    }

    public var count: Int {
        return array.count
    }
    public mutating func enqueue(_ element: UnsafeMutablePointer<T>) -> Int {
        var ret = 0
        dispatchQueue.sync {
            if (isFull) {
                print("is full")
                ret = -1
            }
            array.append(element)
        }
        return ret
    }

    public mutating func dequeue() -> UnsafeMutablePointer<T>? {
        var ret: UnsafeMutablePointer<T>? = nil

        dispatchQueue.sync {
            if isEmpty {
                ret = nil
                //self.empty_mutex.wait(timeout: .distantFuture)
            } else {
                ret = array.removeFirst()
            }
            //self.full_mutex.signal()
        }
        return ret
    }

    public mutating func flush() {
        dispatchQueue.sync {
            for (index, _) in array.enumerated() {
                let p: UnsafeMutablePointer<T>? = array[index]

                let typeName = String(describing: T.self)
                if (typeName == "AVFrame") {
                    var p1 = p as! UnsafeMutablePointer<AVFrame>?
                    av_frame_unref(p1)
                    let cast = withUnsafeMutablePointer(to: &p1){$0}
                                        print("flush")
                    av_frame_free(cast)
                } else {
                    var p1 = p as! UnsafeMutablePointer<AVPacket>?
                    if (p1 == &flushPacket || p1 == &EOFPacket){
                        continue
                    }
                    av_packet_unref(p1)
                    let cast = withUnsafeMutablePointer(to: &p1){$0}

                    av_packet_free(cast)
                }
            }
            array.removeAll()
        }
    }

    func hasEnough(_ count: Int) -> Bool {
        return self.count >= count
    }
}

func swsScale(option: SwsContext, source: UnsafePointer<AVFrame>, target: UnsafePointer<AVFrame>, height: Int32) -> Int32 {

    let sourceData = [
        UnsafePointer<UInt8>(source.pointee.data.0),
        UnsafePointer<UInt8>(source.pointee.data.1),
        UnsafePointer<UInt8>(source.pointee.data.2),
        UnsafePointer<UInt8>(source.pointee.data.3),
        UnsafePointer<UInt8>(source.pointee.data.4),
        UnsafePointer<UInt8>(source.pointee.data.5),
        UnsafePointer<UInt8>(source.pointee.data.6),
        UnsafePointer<UInt8>(source.pointee.data.7),
        ]
    let sourceLineSize = [
        source.pointee.linesize.0,
        source.pointee.linesize.1,
        source.pointee.linesize.2,
        source.pointee.linesize.3,
        source.pointee.linesize.4,
        source.pointee.linesize.5,
        source.pointee.linesize.6,
        source.pointee.linesize.7
    ]

    let targetData = [
        UnsafeMutablePointer<UInt8>(target.pointee.data.0),
        UnsafeMutablePointer<UInt8>(target.pointee.data.1),
        UnsafeMutablePointer<UInt8>(target.pointee.data.2),
        UnsafeMutablePointer<UInt8>(target.pointee.data.3),
        UnsafeMutablePointer<UInt8>(target.pointee.data.4),
        UnsafeMutablePointer<UInt8>(target.pointee.data.5),
        UnsafeMutablePointer<UInt8>(target.pointee.data.6),
        UnsafeMutablePointer<UInt8>(target.pointee.data.7)
    ]
    let targetLineSize = [
        target.pointee.linesize.0,
        target.pointee.linesize.1,
        target.pointee.linesize.2,
        target.pointee.linesize.3,
        target.pointee.linesize.4,
        target.pointee.linesize.5,
        target.pointee.linesize.6,
        target.pointee.linesize.7
    ]

    let result = sws_scale(
        option,
        sourceData,
        sourceLineSize,
        0,
        height,
        targetData,
        targetLineSize
    )
    return result
}

func isErr(_ errnum: Int32, _ prefix: String) -> Bool {
    if errnum < 0 {
        let msg = "Error occurred: \(prefix) \(errnum) " + FF.av_err2str(errnum) + "\n"
        os_log("%@", type: .error, msg)
        return true
    }
    return false
}

func renderAssLine(_ line: String) -> String {
    var plainText = ""
    do {
        let regex = try NSRegularExpression(pattern: "\\{.+?\\}", options: [])
        plainText = regex.stringByReplacingMatches(
            in: line,
            options: [],
            range: NSMakeRange(0, line.count),
            withTemplate: "")
        plainText = plainText.replacingOccurrences(
            of: "\\N", with: "\n")
    } catch {
        print(error)
    }
    return plainText
}

let posTagRegexes = [
    try! NSRegularExpression(pattern: "\\{.*\\\\an?[0-9].*\\}", options: .caseInsensitive),
    try! NSRegularExpression(pattern: "\\{.*\\\\pos.*\\}", options: .caseInsensitive),
    try! NSRegularExpression(pattern: "\\{.*\\\\move.*\\}", options: .caseInsensitive),
    try! NSRegularExpression(pattern: "\\{.*\\\\iclip.*\\}", options: .caseInsensitive),
    try! NSRegularExpression(pattern: "\\{.*\\\\org.*\\}", options: .caseInsensitive),
    try! NSRegularExpression(pattern: "\\{.*\\\\fade.*\\}", options: .caseInsensitive),
    try! NSRegularExpression(pattern: "\\{.*\\\\fad.*\\}", options: .caseInsensitive)
]

let posTagBlackRegexes = [
    try! NSRegularExpression(pattern: "\\{.*\\\\p[0-4].*\\}", options: .caseInsensitive),
]

func getAssTag(_ line: String) -> String {
    var match: NSTextCheckingResult?

    for regex in posTagBlackRegexes {
        match = regex.firstMatch(in: line, options: [], range: NSMakeRange(0, line.count))
        if (match != nil) {
            return "\\p"
        }
    }

    for regex in posTagRegexes {
        match = regex.firstMatch(in: line, options: [], range: NSMakeRange(0, line.count))
        if (match != nil) {
            break
        }
    }

    if (match == nil) {
        return ""
    }

    let r = Range(match!.range, in: line)!
    let lowerBound = String.Index.init(encodedOffset: r.lowerBound.encodedOffset + 2)
    let upperBound = String.Index.init(encodedOffset: r.lowerBound.encodedOffset + 2 + 3)
    return String(line[lowerBound..<upperBound])
}


let VIDEO_SUFFIX = ["mkv", "mp4", "avi"]

func isVideoFile(_ filename: String) -> Bool {
    for suffix in VIDEO_SUFFIX {
        if filename.hasSuffix("." + suffix) {
            return true
        }
    }
    return false
}

func readFileToEndOfFile(_ filepath: String) -> Data {
    guard let fh = FileHandle(forReadingAtPath: filepath) else {
        os_log("failed to open file: %@", type: .error, filepath)
        return Data()
    }
    defer {
        fh.closeFile()
    }
    return fh.readDataToEndOfFile()
}

func convertMStoString(_ ms: Int64) -> String {
    let inSeconds = ms / 1000
    let minute = inSeconds / 60
    let second = inSeconds % 60
    if (second < 10) {
        return "\(minute):0\(second)"
    } else {
        return "\(minute):\(second)"
    }
}

func dataSha1(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))

    data.withUnsafeBytes{ (bytes: UnsafePointer<CChar>)->Void in
        CC_SHA1(bytes, CC_LONG(data.count), &digest)
    }
    let output = NSMutableString(capacity: Int(CC_SHA1_DIGEST_LENGTH))
    for byte in digest {
        output.appendFormat("%02x", byte)
    }
    return output as String
}

extension Data {
    func getSha1() -> String {
        let data = self
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))

        data.withUnsafeBytes{ (bytes: UnsafePointer<CChar>)->Void in
            CC_SHA1(bytes, CC_LONG(data.count), &digest)
        }
        let output = NSMutableString(capacity: Int(CC_SHA1_DIGEST_LENGTH))
        for byte in digest {
            output.appendFormat("%02x", byte)
        }
        return output as String
    }

    func getMD5() -> String {
        let data = self
        var digest = [UInt8](repeating: 0, count:Int(CC_MD5_DIGEST_LENGTH))

        data.withUnsafeBytes{ (bytes: UnsafePointer<CChar>)->Void in
            CC_MD5(bytes, CC_LONG(data.count), &digest)
        }
        let output = NSMutableString(capacity: Int(CC_MD5_DIGEST_LENGTH))
        for byte in digest {
            output.appendFormat("%02x", byte)
        }
        return output as String
    }
}

func getEncoding(_ cfStringEncoding: CFStringEncodings) -> String.Encoding {
    let encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(cfStringEncoding.rawValue)
        )
    )
    return encoding
}

func processMalformedUTF8(_ data: Data) -> Data {
    var data = data
    data.append(0)
    let s = data.withUnsafeBytes { (p: UnsafePointer<CChar>) in String(cString: p) }
    let clean = s.replacingOccurrences(of: "\u{FFFD}", with: "")

    let d = clean.data(using: String.Encoding.utf8)
    return d!
}

extension String.Encoding {
    static let GB18030 = getEncoding(CFStringEncodings.GB_18030_2000)
    static let BIG5 = getEncoding(CFStringEncodings.big5_HKSCS_1999)
    static let Latin5 = getEncoding(CFStringEncodings.isoLatin5)
    static let doslatin2 = getEncoding(CFStringEncodings.dosLatin2)
}

let EncodingMap = [
    "GB18030": String.Encoding.GB18030,
    "BIG5": String.Encoding.BIG5,
    "UTF-8": String.Encoding.utf8,
    "UTF-16": String.Encoding.utf16,
    "ASCII": String.Encoding.ascii,
    "ISO-8859-9": String.Encoding.Latin5,
    "ISO-8859-1": String.Encoding.Latin5,
    "ISO-8859-2": String.Encoding.Latin5,
    "ISO-8859-3": String.Encoding.Latin5,
    "ISO-8859-4": String.Encoding.Latin5,
    "ISO-8859-5": String.Encoding.Latin5,
    "IBM852": String.Encoding.doslatin2,
    "WINDOWS-1252": String.Encoding.windowsCP1252,
]

func detectEncoding(_ data: Data) -> String.Encoding? {
    let uchardetHandler = uchardet_new()
    var ret: Int32 = 0
    data.withUnsafeBytes{ ( bytes: UnsafePointer<CChar> )->Void in
        ret = uchardet_handle_data(uchardetHandler, bytes, data.count - 2)
    }
    uchardet_data_end(uchardetHandler)
    if (ret != 0) {
        uchardet_delete(uchardetHandler)
        os_log("chardet failed", type: .error)
    }
    let charset = uchardet_get_charset(uchardetHandler)
    let charsetString = String.init(cString: charset!)

    uchardet_delete(uchardetHandler)
    let encoding = EncodingMap[charsetString]
    if (encoding == nil) {
        os_log("unknow encoding %@", type: .error, charsetString)
    }
    return encoding
}

func getAVOpt(_ stream: UnsafeMutablePointer<AVStream>, _ opt: String) -> String? {
    guard let opt = av_dict_get(stream.pointee.metadata, opt, nil, 0) else {
        return nil
    }
    return String.init(cString: opt.pointee.value)
}

class MovieGuesser {
    var movieName: String
    var season: Int32?
    var episode: Int32?

    init(_ filename: String) {
        /*
         A few filename examples:

            Silicon.Valley.S01E01.720p.BluRay.x265.ShAaNiG
            Love, Death & Robots - S01E01 - Sonnie's Edge
            CaptainMarvel.2019.1080p.WEB-DL.H264.AC3-EVO
            friends_s01e01_720p_bluray_264-fdaf.mkv
            The Witcher 08 Mo.mkv
        */
        let pattern = "([\\w. &,]+)[-_ ]*([sS]\\d+[eE]\\d+|\\d{2,4})[\\. -_]+.*"

        let regex = try! NSRegularExpression(pattern: pattern,
                                                 options: [])
        let matches = regex.matches(in: filename, options: [], range: NSMakeRange(0, filename.count))
        if (matches.count > 0) {
            let m = matches[0]
            movieName = (filename as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters)
            let part2 = (filename as NSString).substring(with: m.range(at: 2)).lowercased()
            if part2.starts(with: "s") {
                let s = part2[
                    part2.index(part2.startIndex, offsetBy: 1)..<part2.index(of: "e")!]
                let e = part2[
                    part2.index(part2.index(of: "e")!, offsetBy: 1)..<part2.endIndex]
                season = Int32(s)
                episode = Int32(e)
            }
        } else {
            movieName = ""
        }
    }
}
