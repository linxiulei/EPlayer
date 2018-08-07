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
    
    @IBOutlet weak var fileBtn: UIButton!
    @IBOutlet weak var wifiBtn: UIButton!
    @IBOutlet weak var checkAllBox: BEMCheckBox!
    @IBOutlet weak var checkAllBoxWidth: NSLayoutConstraint!
    
    func didTap (_ box: BEMCheckBox) {
        guard let fileListView = fileListView else {
            return
        }
        
        if checkAll {
            checkAll = false
            for cell in fileListView.tableView.visibleCells {
                let fileCell = cell as! FileListCell
                fileCell.checkBox.on = false
            }
            return
        }
        
        for cell in fileListView.tableView.visibleCells {
            let fileCell = cell as! FileListCell
            fileCell.checkBox.on = true
        }
        checkAll = true
    }
    
    @IBAction func clickFile(_ sender: UIButton) {
        guard let fileListView = fileListView else {
            return
        }
        
        if deleteActive {
            sender.setTitle("File", for: UIControlState.normal)
            deleteActive = false
            
            for cell in fileListView.tableView.visibleCells {
                let fileCell = cell as! FileListCell
                if fileCell.checkBox.on {
                    fileCell.checkBox.on = false
                    guard let filename = fileCell.fileName.text else {
                        continue
                    }
                    let movieFileManager = fileListView.movieFileManager
                    movieFileManager.deleteFileByName(filename)
                }
            }

            fileListView.tableView.reloadData()
            for cell in fileListView.tableView.visibleCells {
                let fileCell = cell as! FileListCell
                
                fileCell.checkBox.isHidden = true
                fileCell.checkBoxWidth.constant = 0
            }
            checkAllBox.isHidden = true
            checkAllBoxWidth.constant = 0
            return
        }
        
        deleteActive = true
        sender.setTitle("Delete", for: UIControlState.normal)
        for cell in fileListView.tableView.visibleCells {
            let fileCell = cell as! FileListCell
            fileCell.checkBoxWidth.constant = 30
            fileCell.checkBox.isHidden = false
        }
        checkAllBox.isHidden = false
        checkAllBoxWidth.constant = 30
    }
    
    @IBAction func clickWifi(_ sender: UIButton, forEvent event: UIEvent) {
    }
    
    override func viewDidLoad() {
        checkAllBox.delegate = self
        super.viewDidLoad()
    }
}
