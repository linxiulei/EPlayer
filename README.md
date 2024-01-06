EPlayer
=======

Another iOS Video player application (Swift).

It's an English(Languages) learning oriented Video player, which helps
you download subtitles and look up words you are unfamiliar with.
That would help those who want to learn a second language by watching
videos along with subtitles of that language only.

With my rough experience learning English, it occurs to me that I need
a tool that helps me stand out the words I am not familiar with when
watching English videos and even better if it interprets for me so that I can
consume tons of sitcoms, in the meantime, memorizing that vocabulary
naturally. And I hope this method could apply in other languages learning.

## Features

* Hardware/software decoding support for h264 (others may be supported too, though
  I didn't test)
* Mainstream video formats support
* iOS Simulator(x86) support
* iPhone/iPad(arm64) support and iOS 10.0 higher (Didn't do well with layout
  for iPhone)
* External subtitles support (srt/ass)
* Download subtitles from OpenSubtitles
* Subtitle offset tweak (forward/delay)
* Video move forward/afterward
* Video progress history
* Gesture control (forward/afterward/lightness/volume/pause)

## Snapshots

Definition

![](docs/interpretation.gif)

Move forward

![](docs/progress_control.gif)

Show/Hide control panel

![](docs/hide_panel.gif)

Volume/Lightness control

![](docs/volume_lightness_control.gif)

Pause control

![](docs/pause.gif)

Download/Tweak subtitles

![](docs/download_subtitles.gif)

## Usage

1. Open Xcode -> File/Open EPlayer.xcworkspace
2. Verify your developer certification or let Xcode create one
   automatically for you
3. Plug-in one of your iOS devices or use simulator
4. Choose build target and cmd + r to run this application

**Note**: if you're using a device, try to use iTunes to copy some movies through
Filesharing

## Dependencies and Acknowledges

* FFmpeg
* uchardet
* libass
* AlamofireXMLRPC
* GzipSwift

**Note**: Dependencies were builtin in this repo

This project isn't a sound video player (though it indeed plays sounds),
neither am I an iOS developer. Lots of works are involved to make it an out-of-box
open-source project (due to iOS platform policy). However, it keeps me accompanied
along with many wonderful videos, so I really hope someone with hands-on skills
and a passion for learning languages could enjoy this. Cheers!

Oh, by the way, it really helps me learn a language named Swift 4.0 :-

## Author

Eric Lin, linxiulei@gmail.com

## License

Not figure it out yet

