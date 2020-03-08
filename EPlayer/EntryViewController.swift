//
//  EntryViewController.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/8/6.
//  Copyright © 2018 林守磊. All rights reserved.
//

import os.log
import Foundation
import BEMCheckBox
import FGRoute

class EntryViewController: UIViewController {
    override func viewDidLoad() {
        let panelController = self.childViewControllers[0] as! ControlPanelController
        let fileListController = self.childViewControllers[1] as! FileListViewController

        panelController.fileListView = fileListController
        super.viewDidLoad()
    }
}

class ControlPanelController: UIViewController, BEMCheckBoxDelegate {
    var fileListView: FileListViewController?
    var deleteActive: Bool = false
    var checkAll: Bool = false
    var fileServer: FileServer! = nil
    var fileServerActived = false

    @IBOutlet weak var wifiActiveLabel: UILabel!
    @IBOutlet weak var fileBtn: UIButton!
    @IBOutlet weak var wifiBtn: UIButton!
    @IBOutlet weak var subBtn: UIButton!

    @IBOutlet weak var checkAllBox: BEMCheckBox!
    @IBOutlet weak var checkAllBoxWidth: NSLayoutConstraint!

    @IBAction func clickRefresh(_ sender: UIButton) {
        fileListView?.refreshFile()
    }

    func didTap (_ box: BEMCheckBox) {
        guard let fileListView = fileListView else {
            return
        }

        fileListView.checkAllBoxes(box.on)
    }

    @IBAction func clickSub(_ sender: UIButton) {
        guard let files =  fileListView?.movieFileManager.movieFiles else {
            return
        }
        var count: Int = 0
        for file in files {
            if (!file.isMovie()) {
                continue
            }
            count += 1
            // OpenSubtitle limits 40 requests per 10 seconds per IP
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(5 * count)) {
                downloadSubtitleAndSave(file.path) {(_, _) in
                    
                }
            }

        }
        fileListView?.refreshFile()
    }

    @IBAction func clickFile(_ sender: UIButton) {
        guard let fileListView = fileListView else {
            return
        }

        if deleteActive {
            sender.setTitle("File", for: UIControlState.normal)
            deleteActive = false

            fileListView.deleteCheckedFiles()
            fileListView.checkBoxActived = false
            fileListView.tableView.reloadData()

            checkAllBox.isHidden = true
            checkAllBoxWidth.constant = 0
            return
        }

        fileListView.checkBoxActived = true
        deleteActive = true
        sender.setTitle("Delete", for: UIControlState.normal)
        fileListView.forEachVisibleRow() { (_ cell: FileListCell) in
            cell.checkBoxWidth.constant = 30
            cell.checkBox.isHidden = false
            cell.checkBox.on = false
            cell.checkBox.reload()
        }

        checkAllBox.isHidden = false
        checkAllBoxWidth.constant = 30
        checkAllBox.on = false
    }

    @IBAction func clickWifi(_ sender: UIButton, forEvent event: UIEvent) {
        let port = 8080
        if fileServer == nil {
            fileServer = getFileServer(fileListView!.movieFileManager, "0.0.0.0", port)
        }

        fileServerActived = !fileServerActived

        if fileServerActived {
            guard let ipaddress = FGRoute.getIPAddress() else {
                fileServerActived = false
                return
            }

            wifiActiveLabel.text = "http://\(ipaddress):\(port)/"
        }

        if fileServerActived {
            fileServer.start()
        } else {
            fileServer.stop()
        }
    }

    override func viewDidLoad() {
        checkAllBox.delegate = self
        subBtn.setTitle("Loading", for: UIControlState.highlighted)
        super.viewDidLoad()
    }
}
