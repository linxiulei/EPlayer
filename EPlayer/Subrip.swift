//
//  Subrip.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/4/7.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import os.log
import Foundation

enum SubtitleError: Error {
    case UnknowEncoding
    case ConvertError(desc: String)
    case Invalid(msg: String)
}

let regex1 = try! NSRegularExpression(pattern: "\\<.+?\\>", options: [])
let regex2 = try! NSRegularExpression(pattern: "\\{.+?\\}", options: [])

class Subrip {

    let stripREs = [regex1, regex2]

    var events = [SubEvent]()
    func initWithData (_ data: Data) throws {
        guard let encoding = detectEncoding(data) else {
            throw SubtitleError.UnknowEncoding
        }

        guard let content = String.init(data: data, encoding: encoding) else {
            throw SubtitleError.ConvertError(desc: encoding.description)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        dateFormatter.timeZone = TimeZone.init(abbreviation: "GMT")

        var se = SubEvent()
        var invalidLines = 0
        var errorFlag = false
        for line in content.split(separator: "\r\n", omittingEmptySubsequences: false) {
            if (line == "") {
                events.append(se)
                se = SubEvent()
                errorFlag = false
                continue
            }

            if errorFlag {
                continue
            }

            if (se.serial == -1) {
                if let serial = Int64(line) {
                    se.serial = serial
                } else {
                    invalidLines += 1
                    if (invalidLines) > 20 {
                        throw SubtitleError.Invalid(msg: "Error lines exceed 20")
                    }
                    errorFlag = true
                }

            } else if (se.pts == -1) {
                let components = line.components(separatedBy: " --> ")
                if (components.count != 2) {
                    throw SubtitleError.Invalid(msg: "components of split line " + line + " is not valid")
                }
                let ptsStr0 = components[0]
                let ptsStr1 = components[1]
                let pts0 = dateFormatter.date(from: "1970-01-01 " + ptsStr0)
                let pts1 = dateFormatter.date(from: "1970-01-01 " + ptsStr1)
                if (pts0 == nil) {
                    throw SubtitleError.Invalid(msg: "timestamp of " + ptsStr0 + " is not valid")
                }
                if (pts1 == nil) {
                    throw SubtitleError.Invalid(msg: "timestamp of " + ptsStr1 + " is not valid")
                }
                se.pts = Int64(pts0!.timeIntervalSince1970 * 1000.0)
                se.duration = Int64((pts1!.timeIntervalSince1970 - pts0!.timeIntervalSince1970) * 1000.0)
            } else {
                se.text += renderSubripLine(line + "\n")
                se.tag = getAssTag(String(line))
                if se.tag != "" {
                    print(se.pts)
                    print(se.tag)
                }
            }
        }
    }

    init? (data: Data) throws {
        try initWithData(data)
    }

    init? (filepath: String) {
        let fh = FileHandle(forReadingAtPath: filepath)
        if (fh == nil) {
            os_log("Subrip: failed to open file: %@", type: .error, filepath)
            return nil
        }
        let d = fh!.readDataToEndOfFile()
        do {
            try initWithData(d)
        } catch SubtitleError.UnknowEncoding {
            os_log("unknow encoding with subtitle file %@", type: .error, filepath)
            return nil
        } catch SubtitleError.ConvertError(let desc) {
            os_log("failed to convert with encoding %@", desc)
            return nil
        } catch SubtitleError.Invalid(let msg) {
            os_log("Invalid file: %@ with error: %@", type: .error, filepath, msg)
            return nil
        } catch {
            os_log("Subrip: Unexpected Error %@", error.localizedDescription)
        }
    }

    func renderSubripLine(_ line: String) -> String {
        var plainText = line
        for regex in stripREs {
            plainText = regex.stringByReplacingMatches(
                in: plainText,
                options: [],
                range: NSMakeRange(0, plainText.count),
                withTemplate: "")
        }
        return plainText
    }
}

class SubEvent {
    var serial: Int64
    var pts: Int64
    var duration: Int64
    var text: String
    var tag: String
    init () {
        serial = -1
        self.pts = -1
        self.duration = -1
        self.text = ""
        self.tag = ""
    }

    init(_ s: Int64, _ pts: Int64, _ duration: Int64, _ text: String, _ tag: String) {
        serial = s
        self.pts = pts
        self.duration = duration
        self.text = text
        self.tag = tag
    }
}
