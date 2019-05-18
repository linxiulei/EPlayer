//
//  MoviePanelController.swift
//  EPlayer
//
//  Created by 林守磊 on 2018/4/9.
//  Copyright © 2018 林守磊. All rights reserved.
//

import Foundation


class MoviePanelController: UINavigationController {
    var rootMovieController: MovieViewController?
    var top: MovieInfoController?
    override func viewDidLoad() {
        top = topViewController as? MovieInfoController
        top?.rootMovieController = rootMovieController

        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.barStyle = UIBarStyle.black
        navigationBar.backgroundColor = UIColor.clear
        view.backgroundColor = UIColor.clear

        //setNavigationBarHidden(true, animated: true)
    }

    func reload() {
        guard let view = top?.view as? UITableView else {
            return
        }
        top?.rootMovieController = rootMovieController
        view.reloadData()
    }
}

class MovieInfoController: UITableViewController {
    var rootMovieController: MovieViewController?
    let GENERAL_SECTION_INDEX = 0
    let AUDIO_STREAM_SECTION_INDEX = 1
    let SUBTITLE_STREAM_SECTION_INDEX = 2

    let SECTIONS = ["GENERAL", "AUDIO", "SUBTITLE"]
    let GENERAL_ROWS = ["Play Mode", "Play Rate", "Subtitle Delay"]
    override func viewDidLoad() {
    }

    func getVideo() -> Video? {
        return rootMovieController?.video
    }


    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let video = getVideo() else {
            return 0
        }

        if (section == GENERAL_SECTION_INDEX) {
            return GENERAL_ROWS.count
        } else if (section == SUBTITLE_STREAM_SECTION_INDEX) {
            // one more for download button
            let subtitlesNum = video.getSubtitleStreamNames().count
            if (subtitlesNum > 0) {
                return video.getSubtitleStreamNames().count + 2
            } else {
                return video.getSubtitleStreamNames().count + 1
            }
        } else if (section == AUDIO_STREAM_SECTION_INDEX) {
            return video.getAudioStreamNames().count
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell
        if (indexPath.section == GENERAL_SECTION_INDEX) {
            cell = tableView.dequeueReusableCell(withIdentifier: "GeneralSettingCell", for: indexPath)
            cell.textLabel?.text = GENERAL_ROWS[indexPath.row]
        } else {

            cell = tableView.dequeueReusableCell(withIdentifier: "StreamCell", for: indexPath)
            guard let video = getVideo() else { return cell }

            if (indexPath.section == SUBTITLE_STREAM_SECTION_INDEX) {
                let subtitleNum = video.getSubtitleStreamNames().count
                if (indexPath.row == subtitleNum) {
                    cell.textLabel?.text = "Download More"
                } else if (indexPath.row == subtitleNum + 1) {
                    cell.textLabel?.text = "Disable Subtitle"
                } else {
                    cell.textLabel?.text = video.getSubtitleStreamNames()[indexPath.row]
                }
            } else {
                let audioStreamNames = video.getAudioStreamNames()
                cell.textLabel?.text = "\(audioStreamNames[indexPath.row])"
            }
        }

        cell.backgroundColor = UIColor.clear
        cell.textLabel?.textColor = UIColor.white
        return cell
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return SECTIONS.count
    }

    override func tableView(_ tableView: UITableView,
                   titleForHeaderInSection section: Int) -> String? {
        return SECTIONS[section]
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if (indexPath.section == GENERAL_SECTION_INDEX && GENERAL_ROWS[indexPath.row] == "Subtitle Delay") {
            performSegue(withIdentifier: "subtitleDelay", sender: self)
            return
        }
        guard let video = getVideo() else { return }

        if (indexPath.section == AUDIO_STREAM_SECTION_INDEX) {
            let audioStreamNames = video.getAudioStreamNames()
            video.setAudioStreamByName(audioStreamNames[indexPath.row])
            return
        }

        let subtitleStreams = video.getSubtitleStreamNames()
        if (indexPath.row == subtitleStreams.count) {
           rootMovieController?.downloadSubtitles()
        } else if (indexPath.row == subtitleStreams.count + 1) {
            video.disableSubtitle()
        } else {
            video.setSubtitleStreamByName(subtitleStreams[indexPath.row])
        }
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "subtitleDelay") {
            let dest = segue.destination as! SubtitleDelayController
            dest.video = getVideo()
        }
    }
}
