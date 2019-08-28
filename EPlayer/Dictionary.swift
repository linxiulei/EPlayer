//
//  Dictionary.swift
//  EPlayer
//
//  Created by 林守磊 on 01/04/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os.log
import Foundation

let FORMS = [
    // plural
    ("ves", ""),
    ("ies", ""),
    ("es", ""),
    ("s", ""),

    // third person
    ("ies", "y"),

    // progressive
    ("ing", ""),
    ("ying", "ie"),
    ("ing", "e"),

    // past
    ("ed", ""),
    ("ied", "y"),
    ("ed", "e"),

    // short
    ("'ve", ""),
    ("'s", ""),
    ("n't", ""),
    ("'t", ""),
    ("'re", ""),
    ("'ll", ""),

]

class EPDictionary {

    var mDict = [String: String]()
    var fwordDict = [String: Bool]()
    init(_ fwordFile: String, _ dictFile: String) {
        /*
        //print(mDict)
        mDict["is"] = "是"
        mDict["are"] = "是"
        mDict["have"] = "有"
        mDict["down"] = "向下"
         */
        //fwordDict["you"] = true
        let a = Date().timeIntervalSince1970
        loadDictionary()
        loadFamiliar()
        let b = Date().timeIntervalSince1970
        os_log("initializing dictionary uses %f", type: .debug, b - a)
    }

    func addFamiliarFromFile(_ filepath: String, _ type: String) {
        guard let path = Bundle.main.path(forResource: filepath, ofType: type) else {
            print("no such file \(filepath).\(type)")
            return
        }

        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let lines = data.components(separatedBy: .newlines)
            for l in lines {
                let segments = l.components(separatedBy: ",")
                for seg in segments {
                    fwordDict[seg.lowercased()] = true
                }
            }
        } catch {

        }

    }

    func tryLoadCache(_ filename: String) -> [String: Any] {
        do {
            let filepath = Bundle.main.bundlePath + "/" + filename
            let cacheURL = try! FileManager.default
                .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent(filename + ".cache")

            let attrFile = try FileManager.default.attributesOfItem(atPath: filepath)
            let dateFile = attrFile[FileAttributeKey.modificationDate] as! Date
            let attrCache = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
            let dateCache = attrCache[FileAttributeKey.modificationDate] as! Date

            if (dateCache >= dateFile) {
                let data = try Data(contentsOf: cacheURL, options: [])
                let decoded = try JSONSerialization.jsonObject(with: data, options: [])
                return decoded as! [String: Any]
            }
        } catch {
            print("Unexpected error: \(error).")
        }
        return [String: Any]()
    }

    func loadDictionary() {
        let filename = "dictfile.csv"
        guard let path = Bundle.main.path(forResource: "dictfile", ofType: "csv") else {
            return
        }
        mDict = tryLoadCache(filename) as! [String: String]
        if (mDict.capacity == 0) {
            do {
                let data = try String(contentsOfFile: path, encoding: .utf8)
                let lines = data.components(separatedBy: .newlines)
                for l in lines {
                    let segments = l.components(separatedBy: "\t")
                    if (segments.count > 1) {
                        mDict[segments[0]] = segments[1]
                    }
                }
                let jsonData = try JSONSerialization.data(withJSONObject: mDict)
                let cacheURL = try! FileManager.default
                    .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                    .appendingPathComponent(filename + ".cache")
                FileManager.default.createFile(
                    atPath: cacheURL.path,
                    contents: jsonData,
                    attributes: nil)
            } catch {

            }
        } else {
            print("load cache")
        }
    }

    func loadFamiliar() {
        let filename = "familiar5000.csv"
        let path = Bundle.main.bundlePath + "/" + filename
        fwordDict = tryLoadCache(filename) as! [String: Bool]
        if (fwordDict.capacity == 0) {
            addFamiliarFromFile("familiar5000", "csv")
            addFamiliarFromFile("names", "txt")
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: fwordDict)
                let cacheURL = try! FileManager.default
                    .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                    .appendingPathComponent(filename + ".cache")
                FileManager.default.createFile(
                    atPath: cacheURL.path,
                    contents: jsonData,
                    attributes: nil)
            } catch {}
        } else {
            print("load cache")
        }
    }

    func isFamiliar(_ word: String) -> Bool {
        let wordLowcased = word.lowercased()
        if (fwordDict[wordLowcased] == true) {
            return true
        }

        for (suffix, replace) in FORMS {
            if (wordLowcased.hasSuffix(suffix)) {
                let ret = fwordDict[wordLowcased.dropLast(suffix.count) + replace]
                if (ret == true) {
                    return true
                }
            }
        }
        return false
    }

    func lookup(_ word: String) -> String? {
        let exp = mDict[word]
        return exp
    }

    func lookupWithTransform(_ word: String) -> String? {
        var ret: String?
        for (suffix, replace) in FORMS {
            if (word.hasSuffix(suffix)) {
                ret = lookup(word.dropLast(suffix.count) + replace)
                if (ret != nil) {
                    return ret
                }
            }
        }
        return nil
    }

    func processLine(_ line: String) -> [String: String] {
        var ret = [String: String]()
        var words = [String]()
        let regex = try! NSRegularExpression(pattern: "[a-zA-Z']+")
        regex.enumerateMatches(in: line, range: NSMakeRange(0, line.count)) { match, flags, stop in
            words.append((line as NSString).substring(with: match!.range(at: 0)))
        }

        for w in words {
            let lowcaseWord = w.lowercased()
            if (isFamiliar(lowcaseWord) == false) {
                var exp = lookup(lowcaseWord)
                if (exp == nil) {
                    exp = lookupWithTransform(lowcaseWord)
                }
                if (exp != nil) {
                    ret[lowcaseWord] = exp
                } else {
                    print("Couldn't find a paraprase for \(lowcaseWord)")
                }
            }
        }

        return ret
    }
}
