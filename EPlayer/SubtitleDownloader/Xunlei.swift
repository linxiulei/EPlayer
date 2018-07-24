//
//  Xunlei.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/4/15.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import os.log
import Foundation

let mapping = [
    "简体": "chi",
    "繁体": "chi",
    "英语": "eng",
]

class XLSubinfo: Subinfo {
    var xlSub: XLSubStruct
    init? (_ s: XLSubStruct) {
        if (s.surl == nil) {
            return nil
        }
        xlSub = s
    }
    
    override var ext: String {
        get {
            let segs = xlSub.surl!.split(separator: ".")
            return String.init(segs[segs.count - 1])
        }
    }
    
    override var langs: [String] {
        get {
            var l: [String] = []
            for lang_string in xlSub.language!.split(separator: "&").map(String.init) {
                guard let mapping_lang = mapping[lang_string] else {
                    continue
                }
                l.append(mapping_lang)
            }
            return l
        }
    }
    
    override var link: String {
        get {
            return xlSub.surl!
        }
    }
}



class XLAPI: DownloaderAPI {
    var apiURL = "http://sub.xmp.sandai.net:8000/subxl/%@.json"
    
    func getFileHash(_ filepath: String) -> String {
        guard let fh = FileHandle(forReadingAtPath: filepath) else {
            os_log("error in open file %@", type: .error, filepath)
            return ""
        }
        let fileSize = fh.seekToEndOfFile()
        
        let offsets = [0, fileSize / 3, fileSize - 0x5000]
        let readLength = 0x5000
        
        var d = Data()
        
        for offset in offsets {
            fh.seek(toFileOffset: offset)
            d.append(fh.readData(ofLength: readLength))
        }
        
        return d.getSha1()
    }
    
    
    override func downloadSubtitles(_ videoFilePath: String,
                           _ lang: String,
                           closure: @escaping (_ subinfo: Subinfo) -> Void) {
        
        let hash = getFileHash(videoFilePath)
        let urlString = String(format: apiURL, hash.uppercased())
        
        guard let url = URL(string: urlString) else { return }
        
        var ret: [Subinfo?] = []
        print(url)
        URLSession.shared.dataTask(with: url) { (data, response, error) in
            if error != nil {
                print("Xunlei: \(error!.localizedDescription)")
            }
            
            guard let data = data else { return }
            
            let ndata = processMalformedUTF8(data)
            do {
                let result = try JSONDecoder().decode(XLResult.self, from: ndata)
                for xl in result.sublist {
                    ret.append(XLSubinfo(xl))
                }
                
                for sub in ret {
                    guard let sub = sub else {
                        continue
                    }
                    if sub.langs.contains(lang) {
                        sub.download(closure: closure)
                    }
                }
            } catch let jsonError {
                let dataStr = String(data: ndata, encoding: .utf8)
                print("Xunlei: \(jsonError) \(dataStr)")
            }
        }.resume()
    }
}

struct XLSubStruct: Codable {
    let sname: String?
    let language: String?
    let surl: String?
    let roffset: Int64?
    let rate: String?
    let scid: String?
    let svote: Int64?
}

struct XLResult: Codable {
    let sublist: [XLSubStruct]
}
