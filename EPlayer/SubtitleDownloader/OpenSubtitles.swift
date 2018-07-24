//
//  OpenSubtitles.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/4/21.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import os.log
import Foundation

import Gzip
import Alamofire
import AlamofireXMLRPC


class OpenSubtitleSubinfo: Subinfo {
    var _lang: String
    var _link: String
    var _ext: String
    init(_ link: String, _ ext: String, lang: String) {
        _lang = lang
        _link = link
        _ext = ext
    }
    
    override var ext: String {
        get {
            return _ext
        }
    }
    
    override var langs: [String] {
        get {
            return [_lang]
        }
    }
    
    override var link: String {
        get {
            return _link
        }
    }
    
    override var data: Data? {
        get {
            return try! _data!.gunzipped()
        }
    }
}



class OpenSubtitlesAPI: DownloaderAPI {
    var apiURL = "https://api.opensubtitles.org/xml-rpc"
    
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
    
    
    func logIn(_ mg: MovieGuesser, _ lang: String, closure: @escaping (_ subinfo: Subinfo) -> Void) {
        let params: [Any] = ["", "", "en", "TemporaryUserAgent"]
        AlamofireXMLRPC.request(apiURL, methodName: "LogIn", parameters: params).responseXMLRPC { (response: DataResponse<XMLRPCNode>) -> Void in
            switch response.result {
                case .success(let value):
                    let token = value[0]["token"].string
                    self.searchSubtitles(mg, token!, lang, closure: closure)
                case .failure:
                    print("failure")
            }
            
        }
    }
    
    func searchSubtitles(_ mg: MovieGuesser, _ token: String, _ lang: String, closure: @escaping (_ subinfo: Subinfo) -> Void) {
        var query: [String: Any]
        if (mg.episode != nil) {
            query = ["query": mg.movieName, "season": mg.season!, "episode": mg.episode!, "sublanguageid": lang]
        } else {
            query = ["query": mg.movieName, "sublanguageid": lang]
        }
        let params: [Any] = [
            token,
            [query],
            ["limit": 10]
        ]
        AlamofireXMLRPC.request(apiURL, methodName: "SearchSubtitles", parameters: params).responseXMLRPC { (response: DataResponse<XMLRPCNode>) -> Void in
            switch response.result {
            case .success(let value):
                guard let subtitleList = value[0]["data"].array else {
                    return
                }
                let num = subtitleList.count
                os_log("%d subtitles of %s found in Opensubtitles", type: .info, num, lang)
                
                var subinfoList = [Subinfo]()
                for subtitle in subtitleList {
                    let link = subtitle["SubDownloadLink"].string
                    let ext = subtitle["SubFormat"].string
                    let lang = lang
                    let subinfo = OpenSubtitleSubinfo(link!, ext!, lang: lang)
                    subinfoList.append(subinfo)
                }
    
                for subinfo in subinfoList {
                    subinfo.download(closure: closure)
                }

            case .failure:
                print("failure")
            }
        }
    }
    
    override func downloadSubtitles(_ videoFilePath: String,
                                    _ lang: String,
                                    closure: @escaping (_ subinfo: Subinfo) -> Void) {
        let url = URL(fileURLWithPath: videoFilePath)
        let filename = url.lastPathComponent
        let mg = MovieGuesser(filename)
        if (mg.movieName == "") {
            os_log("couldn't guess the movie info of %@", type: .info, filename)
            return
        }
        logIn(mg, lang, closure: closure)
    }
}
