//
//  Dictionary.swift
//  EPlayer
//
//  Created by 林守磊 on 01/04/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

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
        if let path = Bundle.main.path(forResource: "dictfile", ofType: "csv") {
            do {
                let data = try String(contentsOfFile: path, encoding: .utf8)
                let lines = data.components(separatedBy: .newlines)
                for l in lines {
                    let segments = l.components(separatedBy: "\t")
                    if (segments.count > 1) {
                        mDict[segments[0]] = segments[1]
                    }
                }
            } catch {

            }
        }
        /*
        //print(mDict)
        mDict["is"] = "是"
        mDict["are"] = "是"
        mDict["have"] = "有"
        mDict["down"] = "向下"
         */
        //fwordDict["you"] = true

        if let path = Bundle.main.path(forResource: "farmiliar5000", ofType: "csv") {
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
