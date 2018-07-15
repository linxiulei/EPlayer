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
            return xlSub.language!.split(separator: "&").map(String.init)
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
        URLSession.shared.dataTask(with: url) { (data, response, error) in
            if error != nil {
                print("Xunlei: \(error!.localizedDescription)")
            }
            
            guard let data = data else { return }
            do {
                let result = try JSONDecoder().decode(XLResult.self, from: data)
                for xl in result.sublist {
                    ret.append(XLSubinfo(xl))
                }
                
                for sub in ret {
                    guard let sub = sub else {
                        continue
                    }
                    sub.download(closure: closure)
                }
            } catch let jsonError {
                let dataStr = String(data: data, encoding: String.Encoding.ascii)
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
