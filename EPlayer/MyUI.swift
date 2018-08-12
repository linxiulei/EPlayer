//
//  MyUI.swift
//  EPlayer
//
//  Created by 林守磊 on 26/03/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

import Foundation

class MovieProgress: UISlider {
    var video: Video?
    required init(_ v: Video) {
        video = v
        super.init(frame: .zero)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
