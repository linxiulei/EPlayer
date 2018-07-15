//
//  Shooter.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/4/15.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import os.log
import Foundation


class ShooterSubinfo: Subinfo {
    var apiFileStruct: ShooterAPISubFileStruct
    var lang: String
    init(_ s: ShooterAPISubFileStruct, _ lang: String) {
        apiFileStruct = s
        self.lang = lang
    }
    
    override var ext: String {
        get {
            return apiFileStruct.Ext
        }
    }
    
    override var langs: [String] {
        get {
            return [lang]
        }
    }
    
    override var link: String {
        get {
            return apiFileStruct.Link
        }
    }
}



class ShooterAPI: DownloaderAPI {
    var apiURL = "https://www.shooter.cn/api/subapi.php"
    
    func getFileHash(_ filepath: String) -> String {
        guard let fh = FileHandle(forReadingAtPath: filepath) else {
            os_log("error in open file %@", type: .error, filepath)
            return ""
        }
        
        let fileSize = fh.seekToEndOfFile()
        
        let offsets = [4096, fileSize / 3 * 2, fileSize / 3, fileSize - 8192]
        let readLength = 4096
        
        var ret = [String]()
        for offset in offsets {
            fh.seek(toFileOffset: offset)
            let d = fh.readData(ofLength: readLength)
            ret.append(d.getMD5())
        }

        return ret.joined(separator: ":")
    }
    
    
    override func downloadSubtitles(_ videoFilePath: String,
                           _ lang: String,
                           closure: @escaping (_ subinfo: Subinfo) -> Void) {
        let hash = getFileHash(videoFilePath)

        guard var urlComponents =  URLComponents(string: apiURL) else {
            os_log("init url components failed", type: .error)
            return
        }
        let values: [String: String] = [
            "filehash": hash,
            "pathinfo": "",
            "format": "json",
            "lang" : lang
        ]
        
        var queryItems = [URLQueryItem]()
        for (k, v) in values {
            let item = URLQueryItem(name: k, value: v)
            queryItems.append(item)
        }
        
        urlComponents.queryItems = queryItems

        var ret: [ShooterSubinfo] = []
        urlComponents.percentEncodedQuery = urlComponents.percentEncodedQuery?.replacingOccurrences(of: ":", with: "%3B")
        URLSession.shared.dataTask(with: urlComponents.url!) { (data, response, error) in
            if error != nil {
                print("shooter: \(error!.localizedDescription)")
            }
            
            guard let data = data else { return }
            if (data[0] == 255) {
                os_log("No subtitles found from Shooter")
                return
            }
            do {
                let result = try JSONDecoder().decode([ShooterAPISubStruct].self, from: data)
                for shootAPISubStruct in result {
                    for file in shootAPISubStruct.Files {
                        ret.append(ShooterSubinfo(file, lang))
                    }
                }

                for sub in ret {
                    sub.download(closure: closure)
                }
            } catch let jsonError {
                let dataStr = String(data: data, encoding: String.Encoding.ascii)
                print("Shooter: \(jsonError) \(dataStr)")
            }
        }.resume()
    }
}

struct ShooterAPISubStruct: Codable {
    let Delay: Int
    let Desc: String
    let Files: [ShooterAPISubFileStruct]
}

struct ShooterAPISubFileStruct: Codable {
    let Ext: String
    let Link: String
}

struct ShooterAPIResultStruct: Codable {
    let sublist: [ShooterAPISubStruct]
}
