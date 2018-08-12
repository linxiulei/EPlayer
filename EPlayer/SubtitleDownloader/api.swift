//
//  api.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/4/15.
//  Copyright © 2018 林守磊. All rights reserved.
//

import Foundation

class Subinfo {
    var _data: Data?
    init () {}
    var ext: String {
        get {
            return ""
        }
    }

    var langs: [String] {
        get {
            return [""]
        }
    }

    var link: String {
        get {
            return ""
        }
    }

    var data: Data? {
        get {
            return _data
        }
    }

    func download(closure: @escaping (_ subinfo: Subinfo) -> Void) {
        let subURL = URL(string: link)
        URLSession.shared.dataTask(with: subURL!) { (data, response, error) in
            if error != nil {
                print(error!.localizedDescription)
            }

            guard let data = data else { return }
            self._data = data
            closure(self)
        }.resume()
    }
}

class DownloaderAPI {
    init() {}

    func downloadSubtitles(_ videoFilePath: String,
                           _ lang: String,
                           closure: @escaping (_ subinfo: Subinfo) -> Void) {}
}
