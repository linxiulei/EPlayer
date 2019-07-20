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
            return try? _data!.gunzipped()
        }
    }
}



class OpenSubtitlesAPI: DownloaderAPI {
    var apiURL = "https://api.opensubtitles.org/xml-rpc"

    func logIn(_ mg: MovieGuesser, _ hash: OpenSubtitlesHash.VideoHash, _ lang: String, closure: @escaping (_ subinfo: Subinfo) -> Void) {
        let params: [Any] = ["", "", "en", "TemporaryUserAgent"]
        AlamofireXMLRPC.request(apiURL, methodName: "LogIn", parameters: params).responseXMLRPC { (response: DataResponse<XMLRPCNode>) -> Void in
            switch response.result {
                case .success(let value):
                    let token = value[0]["token"].string
                    if (token == nil) {
                        print("OpenSubtitle LogIn API failed")
                        return
                    }
                    self.searchSubtitles(nil, hash, token!, lang, closure: closure)
                    self.searchSubtitles(mg, nil, token!, lang, closure: closure)
                case .failure:
                    print("failure")
            }

        }
    }
    func generateQuery(_ mg: MovieGuesser?, _ hash: OpenSubtitlesHash.VideoHash?) -> [String: Any] {
        var query: [String: Any]
        guard let mg = mg else {
            query = ["moviehash": hash!.fileHash, "moviebytesize": hash!.fileSize]
            return query
        }

        if (mg.episode != nil) {
            query = ["query": mg.movieName, "season": mg.season!, "episode": mg.episode!]
        } else {
            query = ["query": mg.movieName]
        }
        return query
    }

    func searchSubtitles(_ mg: MovieGuesser?, _ hash: OpenSubtitlesHash.VideoHash?, _ token: String, _ lang: String, closure: @escaping (_ subinfo: Subinfo) -> Void) {
        var query = self.generateQuery(mg, hash)
        query["sublanguageid"] = lang
        let params: [Any] = [
            token,
            [query],
            ["limit": 10]
        ]
        print(apiURL)
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
        let hash = OpenSubtitlesHash.hashFor(url)
        if (mg.movieName == "") {
            os_log("couldn't guess the movie info of %@", type: .info, filename)
            return
        }
        logIn(mg, hash, lang, closure: closure)
    }
}

//
//  This Swift 3 version is based on Swift 2 version by eduo:
//  https://gist.github.com/eduo/7188bb0029f3bcbf03d4
//
//  Created by Niklas Berglund on 2017-01-01.
//
class OpenSubtitlesHash: NSObject {
    static let chunkSize: Int = 65536

    struct VideoHash {
        var fileHash: String
        var fileSize: UInt64
    }

    public class func hashFor(_ url: URL) -> VideoHash {
        return self.hashFor(url.path)
    }

    public class func hashFor(_ path: String) -> VideoHash {
        var fileHash = VideoHash(fileHash: "", fileSize: 0)
        let fileHandler = FileHandle(forReadingAtPath: path)!

        let fileDataBegin: NSData = fileHandler.readData(ofLength: chunkSize) as NSData
        fileHandler.seekToEndOfFile()

        let fileSize: UInt64 = fileHandler.offsetInFile
        if (UInt64(chunkSize) > fileSize) {
            return fileHash
        }

        fileHandler.seek(toFileOffset: max(0, fileSize - UInt64(chunkSize)))
        let fileDataEnd: NSData = fileHandler.readData(ofLength: chunkSize) as NSData

        var hash: UInt64 = fileSize

        var data_bytes = UnsafeBufferPointer<UInt64>(
            start: UnsafePointer(fileDataBegin.bytes.assumingMemoryBound(to: UInt64.self)),
            count: fileDataBegin.length/MemoryLayout<UInt64>.size
        )

        hash = data_bytes.reduce(hash,&+)

        data_bytes = UnsafeBufferPointer<UInt64>(
            start: UnsafePointer(fileDataEnd.bytes.assumingMemoryBound(to: UInt64.self)),
            count: fileDataEnd.length/MemoryLayout<UInt64>.size
        )

        hash = data_bytes.reduce(hash,&+)

        fileHash.fileHash = String(format:"%016qx", arguments: [hash])
        fileHash.fileSize = fileSize

        fileHandler.closeFile()

        return fileHash
    }
}
