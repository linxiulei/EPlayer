//
//  FileServer.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/8/11.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os
import os.log
import Foundation

import Embassy
import FGRoute

let CodeStatus = [
    200: "OK",
    404: "Not Found"
]


class HTTPResponse {
    var code: Int = 0
    var headers: [(String, String)] = []
    var data: Data = Data()
    init() {

    }

    init(_ code: Int) {
        self.code = code
    }

    init(_ code: Int, _ data: Data) {
        self.code = code
        self.data = data
    }

    func setCode(_ code: Int) {
        self.code = code
    }

    func setData(_ data: Data) {
        self.data = data
    }

    func addHeader(_ key: String, _ value: String) {
        headers.append((key, value))
    }

    func getCodeStatus() -> String {
        guard let status = CodeStatus[code] else {
            return "code not found"
        }
        return "\(code) \(status)"
    }
}


class FileServer {
    var loop: EventLoop
    var server: HTTPServer? = nil
    var movieFileManager: MovieFileManager
    var handlers: [String : ((_ environ: [String: Any], _ closure: @escaping (HTTPResponse) -> Void) -> Void)] = [:]

    init(_ fileManager: MovieFileManager, _ bind: String, _ port: Int) {
        movieFileManager = fileManager
        loop = try! SelectorEventLoop(selector: try! KqueueSelector())
        server = DefaultHTTPServer(eventLoop: loop, interface: bind, port: port) {
            (
            environ: [String: Any],
            startResponse: @escaping ((String, [(String, String)]) -> Void),
            sendBody: @escaping ((Data) -> Void)
            ) in
            let pathInfo = environ["PATH_INFO"]! as! String
            guard let handler = self.handlers[pathInfo] else {
                startResponse("404 Not Found", [])
                sendBody(Data("path not found".utf8))
                sendBody(Data())
                return
            }
            handler(environ) { response in
                startResponse(response.getCodeStatus(), response.headers)
                sendBody(response.data)
                sendBody(Data())
            }
        }

    }

    func registerHandler(_ path: String,
                         _ handler:@escaping (_ environ: [String: Any], _ closure:@escaping (HTTPResponse) -> Void) -> Void) {
        handlers[path] = handler
    }

    func start() {
        guard let server = server else {
            return
        }
        try! server.start()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now()) {
            self.loop.runForever()
        }
    }

    func stop() {
        guard let server = server else {
            return
        }

        server.stop()
    }

    func indexHandler(_ environ: [String: Any], _ closure: (HTTPResponse) -> Void) -> Void {
        let data = Data("""
        <html>
            <head>
                <title>Upload Files</title>
            </head>

            <body>
                <div id="post_form">
                    <form action="upload" enctype="multipart/form-data" method="post">
                        <input type="file" name="files" multiple="multiple">
                        <br/>
                        <input type="submit" value="submit">
                    </form>
                </div>
            </body>

        </html>
        """.utf8)
        let r = HTTPResponse()
        r.setCode(200)
        r.setData(data)
        closure(r)
    }

    func postFileAPIHandler (_ environ: [String: Any], _ closure: @escaping (HTTPResponse) -> Void) -> Void {
        let r = HTTPResponse(200, Data("OK".utf8))
        let filenameQuery = environ["QUERY_STRING"] as? String

        let queries = filenameQuery!.components(separatedBy: "&")
        var filename = ""
        for q in queries {
            let queryFields = q.components(separatedBy: "=")
            if queryFields[0] == "filename" {
                filename = queryFields[1]
            }
        }
        guard filename != "" else {
            closure(HTTPResponse(404, Data("filename not provided".utf8)))
            return
        }
        self.movieFileManager.createFile(filename, true)
        let fileHandle = self.movieFileManager.getFileHandle(filename)
        let input = environ["swsgi.input"] as! SWSGIInput
        input { data in
            if data.count == 0 {
                closure(r)
            }
            fileHandle.write(data)
        }
    }

    func postFileHandler(_ environ: [String: Any], _ closure: @escaping (HTTPResponse) -> Void) -> Void {
        let r = HTTPResponse(200)

        guard let contentTypeAny = environ["CONTENT_TYPE"] else {
            r.setCode(404)
            r.setData(Data("File Not Found".utf8))
            closure(r)
            return
        }

        let contentType = contentTypeAny as! String

        let segs = contentType.components(separatedBy: "; ")
        var boundary: String? = nil
        for s in segs {
            if s.starts(with: "boundary=") {
                let fields = s.components(separatedBy: "=")
                boundary = fields[1]
            }
        }

        guard boundary != nil else {
            closure(HTTPResponse(404))
            return
        }
        
        let input = environ["swsgi.input"] as! SWSGIInput

        let parser = MultiPartParser(boundary!)


        var fileHandle: FileHandle! = nil
        input { data in
            //os_log("%@", String(data: data, encoding: String.Encoding.utf8)!)
            let results = parser.feed(data)

            for r in results {
                if r.d.count > 0 {
                    if fileHandle == nil {
                        print("ERROR FileServer")
                    }
                    fileHandle.write(r.d)
                }

                if r.headers.count > 0 {
                    for header in r.headers {
                        if header.0 == "Content-Disposition" {
                            let filename = getHeaderFilename(header.1)
                            self.movieFileManager.createFile(filename, true)
                            fileHandle = self.movieFileManager.getFileHandle(filename)
                        }
                    }
                }
            }

            if data.count == 0 {
                r.setCode(200)
                r.setData(Data("OK".utf8))
                closure(r)
            }
        }
    }
}

func getFileServer(_ fileManager: MovieFileManager, _ bind: String, _ port: Int) -> FileServer {
    let f = FileServer(fileManager, bind, port)
    f.registerHandler("/", f.indexHandler)
    f.registerHandler("/upload", f.postFileHandler)
    f.registerHandler("/api/upload", f.postFileAPIHandler)
    return f
}


class MultiPartParser {
    var boundary: String
    var _leftover = Data()
    var headerParser: HTTPHeaderParser!

    init (_ boundary: String) {
        self.boundary = boundary
    }

    func feed(_ data: Data) -> [(d: Data, headers: [(String, String)])] {
        self._leftover += data
        var r: [(d: Data, headers: [(String, String)])] = []
        var lastLeftover = Data()
        repeat {
            lastLeftover = self._leftover
            let result = getNext(self._leftover)

            if result.d.count > 0 || result.headers.count > 0 {
                r.append((result.d, result.headers))
            }
            self._leftover = result.leftover

        } while lastLeftover != self._leftover

        return r
    }

    func getNext(_ data: Data) -> (d: Data, headers: [(String, String)], leftover: Data) {
        let b = "--" + self.boundary + "\r\n"
        let end = "--" + self.boundary + "--\r\n"

        let fullData = data
        var leftover = Data()
        var d = Data()

        if fullData.count < b.count {
            return (Data(), [], fullData)
        }

        let str = String(data: fullData, encoding: String.Encoding.ascii)!

        if headerParser != nil {
            let result = feedHeaders(data)
            if result.leftover.count != 0 {
                headerParser = nil
            }

            return (Data(), result.headers, result.leftover)
        }

        guard let range = str.range(of: b) else {
            if str.range(of: end) != nil {
                d = fullData.subdata(in: 0..<(fullData.count - end.count - 2))
                return (d, [], Data())
            }

            let d = fullData.subdata(in: 0..<(fullData.count - b.count))
            leftover = fullData.subdata(in: (fullData.count - b.count)..<fullData.count)
            return (d, [], leftover)
        }

        // len(CRLF) == 2
        var dataEnd = range.lowerBound.encodedOffset
        if range.lowerBound.encodedOffset > 0 {
            dataEnd -= 2
        }
        d = fullData[..<dataEnd]
        leftover = fullData[(range.lowerBound.encodedOffset + b.count + 1)..<fullData.count]


        headerParser = HTTPHeaderParser()
        return (d, [], leftover)
    }

    func feedHeaders(_ data: Data) -> (headers: [(String, String)], leftover: Data) {
        var leftover = Data()
        if headerParser == nil {
            return ([], leftover)
        }
        var elements: [HTTPHeaderParser.Element] = []
        elements += headerParser.feed(data)

        var headers: [(String, String)] = []
        for element in elements {
            switch element {
            case .header(let key, let value):
                headers.append((key, value))
            case .end(let bodyPart):
                leftover += bodyPart
            case .head(let method, let path, let version):
                print("error")
            }
        }

        return (headers, leftover)
    }
}

//
//  HTTPHeaderParser.swift
//  Embassy
//
//  Created by Fang-Pen Lin on 5/19/16.
//  Copyright © 2016 Fang-Pen Lin. All rights reserved.
//

extension String {
    /// String without leading spaces
    var withoutLeadingSpaces: String {
        var firstNoneSpace: Int = count
        for (i, char) in enumerated() {
            if char != " " {
                firstNoneSpace = i
                break
            }
        }
        return String(suffix(from: index(startIndex, offsetBy: firstNoneSpace)))
    }

    func find(_ subStr: String) -> Int {
        let re = try! NSRegularExpression(pattern: subStr)
        guard let match = re.firstMatch(in: self, range: NSMakeRange(0, self.count)) else {
            return -1
        }
        return match.range.location
    }
}

/// Parser for HTTP headers
public struct HTTPHeaderParser {
    private static let CR = UInt8(13)
    private static let LF = UInt8(10)
    private static let NEWLINE = (CR, LF)

    public enum Element {
        case head(method: String, path: String, version: String)
        case header(key: String, value: String)
        case end(bodyPart: Data)
    }

    private enum State {
        case head
        case headers
    }
    private var state: State = .headers
    private var buffer: Data = Data()

    /// Feed data to HTTP parser
    ///  - Parameter data: the data to feed
    ///  - Returns: parsed headers elements
    mutating func feed(_ data: Data) -> [Element] {
        buffer.append(data)
        var elements = [Element]()
        while buffer.count > 0 {
            // pair of (0th, 1st), (1st, 2nd), (2nd, 3rd) ... chars, so that we can find <LF><CR>
            let charPairs: [(UInt8, UInt8)] = Array(zip(
                buffer[0..<buffer.count - 1],
                buffer[1..<buffer.count]
            ))
            // ensure we have <CR><LF> in current buffer
            guard let index = (charPairs).index(where: { $0 == HTTPHeaderParser.NEWLINE }) else {
                // no <CR><LF> found, just return the current elements
                return elements
            }
            let bytes = Array(buffer[0..<index])
            let string = String(bytes: bytes, encoding: String.Encoding.utf8)!
            buffer = buffer.subdata(in: (index + 2)..<buffer.count)

            // TODO: the initial usage of this HTTP server is for iOS API server mocking only,
            // we don't usually see malform requests, but if it's necessary, like if we want to put
            // this server in real production, we should handle malform header then
            switch state {
            case .head:
                let parts = string.components(separatedBy: " ")
                elements.append(.head(method: parts[0], path: parts[1], version: parts[2..<parts.count].joined(separator: " ")))
                state = .headers
            case .headers:
                // end of headers
                guard bytes.count > 0 else {
                    elements.append(.end(bodyPart: buffer))
                    return elements
                }
                let parts = string.components(separatedBy: ":")
                let key = parts[0]
                let value = parts[1..<parts.count].joined(separator: ":").withoutLeadingSpaces
                elements.append(.header(key: key, value: value))
            }
        }
        return elements
    }
}

func getHeaderFilename(_ contentDisposition: String) -> String {
    // "form-data; name="files"; filename="1"
    let filenameField = contentDisposition.components(separatedBy: "; ")[2]
    var filename = filenameField.components(separatedBy: "=")[1]
    filename.removeFirst()
    filename.removeLast()
    return filename
}
