//
//  FileListViewController.swift
//  EPlayer
//
//  Created by 林守磊 on 27/03/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

import UIKit
import os
import os.log
import BEMCheckBox

class FileListCell: UITableViewCell, BEMCheckBoxDelegate {
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var progress: UILabel!
    @IBOutlet weak var checkBox: BEMCheckBox!
    @IBOutlet weak var checkBoxWidth: NSLayoutConstraint!
    var tapCallback: (() -> ())?

    func didTap (_ box: BEMCheckBox) {
        tapCallback!()
    }
}

class FileListViewController: UITableViewController {
    var movieFileManager = MovieFileManager()
    var checkBoxActived: Bool = false
    var checkBoxChecked: [Bool] = []

    /*
    override var shouldAutorotate: Bool {
        return true
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return UIInterfaceOrientation.landscapeLeft
    }
 */
    func refreshFile () {
        movieFileManager = MovieFileManager()
        checkBoxChecked = [Bool](repeating: false, count: movieFileManager.getFileCount())
        tableView.reloadData()
    }

    func deleteCheckedFiles () {
        for i in (0..<checkBoxChecked.count).reversed() {
            if checkBoxChecked[i]{
                checkBoxChecked.remove(at: i)
                movieFileManager.deleteFileByIndex(i)
            }
        }
    }

    func forEachVisibleRow (closure: @escaping (_ cell: FileListCell) -> Void) {
        let section = 0
        let rows = tableView.numberOfRows(inSection: section)
        for r in 0..<rows {
            guard let cell = tableView.cellForRow(at: IndexPath(row: r, section: section)) as? FileListCell else {
                return
            }
            closure(cell)
        }
    }

    func checkAllBoxes(_ check: Bool) {
        for i in 0..<checkBoxChecked.count {
            checkBoxChecked[i] = check
        }

        forEachVisibleRow() { (_ cell: FileListCell) in
            cell.checkBox.on = check
        }
    }

    override func viewDidLoad() {

        checkBoxChecked = [Bool](repeating: false, count: movieFileManager.getFileCount())
        /*
        print(UIDevice.current.orientation.rawValue)
        let value = UIInterfaceOrientation.landscapeRight.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
        print(UIDevice.current.orientation.rawValue)

        UIViewController.attemptRotationToDeviceOrientation()
 */

        super.viewDidLoad()


        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return movieFileManager.getFileCount()
    }

    override func tableView(_ tableView: UITableView,
                            didEndDisplaying cell: UITableViewCell,
                            forRowAt indexPath: IndexPath) {
        let cell = cell as! FileListCell
        if checkBoxActived {
            checkBoxChecked[indexPath.row] = cell.checkBox.on
        }
        cell.checkBox.on = false
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileListCell
        let movieFile = movieFileManager.getMovieFileByIndex(indexPath.row)
        cell.fileName.text = movieFile.getName()
        cell.checkBox.delegate = cell

        func tapCB () {
            checkBoxChecked[indexPath.row] = !checkBoxChecked[indexPath.row]
        }

        cell.tapCallback = tapCB


        if checkBoxActived {
            cell.checkBox.isHidden = false
            cell.checkBoxWidth.constant = 30


            cell.checkBox.on = checkBoxChecked[indexPath.row]
        } else {
            cell.checkBox.isHidden = true
            cell.checkBoxWidth.constant = 0
        }
        if movieFile.isMovie() {
            cell.progress.text = "\(movieFile.getProgress())%"
        } else {
            cell.progress.text = ""
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        //performSegue(withIdentifier: "fileURL", sender: fileList[indexPath.row])
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "fileURL") {
            guard let fileIndex = tableView.indexPathForSelectedRow?.row else {
                return
            }
            let dest: MovieViewController = segue.destination as! MovieViewController
            let movieFile = movieFileManager.getMovieFileByIndex(fileIndex)
            if !movieFile.isMovie() {
                return
            }
            dest.movieFileManager = movieFileManager
            movieFileManager.setCurIndex(fileIndex)
        }
    }

    @IBAction func unwindToTable(sender: UIStoryboardSegue) {
        let sourceController = sender.source as! MovieViewController
        sourceController.updateTimer?.invalidate()
        sourceController.video?.stop()
        sourceController.video?.deinit0()
        movieFileManager.saveState()
        let view = self.view as! UITableView
        view.reloadData()
    }
}

enum FileCategory {
    case Movie
    case Subtitle
    case Directory
    case Unknown
}

struct StateFile: Codable {
    var fileDict = [String: State]()
}

struct State: Codable {
    var progress: Int = 0
}

class MovieFile {
    var path: String
    var url: URL
    var progress = 0
    // https://en.wikipedia.org/wiki/Video_file_format
    let VIDEO_SUFFIX = [
        "mkv", "mp4", "avi", "mpg", "wmv",
        "mov", "flv", "rmvb", "rm", "3pg"
    ]
    let SUBTITLE_SUFFIX = ["ass", "ssa", "srt"]

    init(_ path: String, _ url: URL) {
        self.path = path
        self.url = url
    }

    func getCategory() -> FileCategory {
        if VIDEO_SUFFIX.contains(url.pathExtension.lowercased()) {
            return FileCategory.Movie
        }

        if SUBTITLE_SUFFIX.contains(url.pathExtension.lowercased()) {
            return FileCategory.Subtitle
        }

        if isDir() {
            return FileCategory.Directory
        }

        os_log("unknow category %@", type: .debug, path)
        return FileCategory.Unknown
    }

    func getType() -> String {
        return url.pathExtension
    }

    func getProgress() -> Int {
        return progress
    }

    func setProgress(_ progress: Int) {
        self.progress = progress
    }

    func isMovie() -> Bool {
        return getCategory() == FileCategory.Movie
    }

    func isDir() -> Bool {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return false
    }

    func getName() -> String {
        return url.lastPathComponent
    }

    func delete() {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: path)
        }
        catch let error as NSError {
            print("Ooops! Something went wrong: \(error)")
        }

    }
}


class MovieFileManager {
    var movieFiles = [MovieFile]()
    var dir: String
    var stateFilePath: String
    var curIndex: Int = 0
    var documentsURL: URL
    var libraryURL: URL
    init() {
        let fileManager = FileManager.default
        documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        dir = documentsURL.path
        stateFilePath = libraryURL.appendingPathComponent("movie_file_state.json").path
        let sf = loadState()

        do {
            var fileURLs = try fileManager.contentsOfDirectory(at: documentsURL,
                                                               includingPropertiesForKeys: nil)
            fileURLs = fileURLs.sorted { url1, url2 in
                return url1.lastPathComponent < url2.lastPathComponent
            }
            for url in fileURLs {
                let m = MovieFile(url.path, url)
                guard let state = sf?.fileDict[m.getName()] else {
                    movieFiles.append(m)
                    continue
                }
                m.progress = state.progress
                movieFiles.append(m)

            }
        } catch {
            print("Error occurs while walking directory")
        }
    }

    func deleteFileByName(_ filename: String) {
        let fileManager = FileManager.default
        var index: Int = 0
        for m in movieFiles {
            if m.getName() == filename {
                movieFiles.remove(at: index)
                m.delete()
                break
            }
            index += 1
        }

        do {
            let filepath = documentsURL.appendingPathComponent(filename).path
            try fileManager.removeItem(atPath: filepath)
        }
        catch let error as NSError {
            print("Ooops! Something went wrong: \(error)")
        }
    }

    func deleteFileByIndex(_ index: Int) {
        movieFiles[index].delete()
        movieFiles.remove(at: index)
    }

    func deleteFileByIndexes(_ indexes: [Int]) {
        var newIndexes = indexes
        newIndexes.sort()
        newIndexes.reverse()
        for i in newIndexes {
            deleteFileByIndex(i)
        }
    }

    func writeFile(_ filename: String, _ data: Data) {
        let fileUrl = documentsURL.appendingPathComponent(filename)
        try! data.write(to: fileUrl)
    }

    func getFileHandle(_ filename: String) -> FileHandle {
        let filepath = documentsURL.appendingPathComponent(filename).path

        return FileHandle(forWritingAtPath: filepath)!
    }

    func createFile(_ filename: String, _ recreate: Bool) {
        let filepath = documentsURL.appendingPathComponent(filename).path
        try? FileManager.default.removeItem(atPath: filepath)
        FileManager.default.createFile(atPath: filepath, contents: nil, attributes: nil)
    }

    func getFileCount() -> Int {
        return movieFiles.count
    }

    func getFilePathByIndex(_ index: Int) -> String {
        return movieFiles[index].path
    }

    func getFileNameByIndex(_ index: Int) -> String {
        return movieFiles[index].url.lastPathComponent
    }

    func getMovieFileByIndex(_ index: Int) -> MovieFile {
        return movieFiles[index]
    }

    func getCurMovieFile() -> MovieFile {
        return movieFiles[curIndex]
    }

    func setCurIndex(_ index: Int) {
        curIndex = index
    }

    func getCurIndex() -> Int {
        return curIndex
    }

    func loadState() -> StateFile? {
        let data = readFileToEndOfFile(stateFilePath)
        do {
            let sf = try JSONDecoder().decode(StateFile.self, from: data)
            return sf
        } catch {
            os_log("loadState decoding StateFile is failed", type: .error)
            return nil
        }
    }

    func saveState() {
        var sf = StateFile()
        for movieFile in movieFiles {
            var state = State()
            state.progress = movieFile.getProgress()
            sf.fileDict[movieFile.getName()] = state
        }
        do {
            let data = try JSONEncoder().encode(sf)
            FileManager.default.createFile(
                atPath: stateFilePath,
                contents: data,
                attributes: nil)
        } catch {
            os_log("saveState encoding StateFile is failed")
        }
    }
}
