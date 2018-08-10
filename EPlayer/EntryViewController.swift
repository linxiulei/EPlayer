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
    
    @IBAction func clickRefresh(_ sender: UIButton) {
        fileListView?.refreshFile()
    }
    
    func didTap (_ box: BEMCheckBox) {
        guard let fileListView = fileListView else {
            return
        }

        fileListView.checkAllBoxes(box.on)
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
    }
    
    override func viewDidLoad() {
        checkAllBox.delegate = self
        super.viewDidLoad()
    }
}
