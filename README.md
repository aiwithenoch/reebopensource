# Reeb

[![Support Reeb](https://img.shields.io/badge/💛_Support_Reeb-17_backers-FFC933?style=for-the-badge)](https://dodo.pe/reeb)
[![License: MIT](https://img.shields.io/badge/License-MIT-0B0E12?style=for-the-badge)](LICENSE)
[![Waitlist](https://img.shields.io/badge/Join_the_waitlist-Be_the_first_Reeber-1B8F4A?style=for-the-badge)](https://tally.so/r/44RV05)

A teleprompter for iOS that scrolls **because you're talking** — not because a timer said so.

Read, and the script moves. Pause, and it waits. Go off-script, and it holds your place until you come back. Speech recognition runs entirely on the phone: no account, no API key, no server, no subscription.

Built with [Claude Code](https://claude.com/claude-code) in an afternoon. Open sourced so you can build your own.

📱 [Demo on TikTok](https://www.tiktok.com/@aiwithenoch/video/7668759110187273490)

> ### 💛 Reeb is free, and it stays free
> **17 people have already chipped in.** Support goes straight toward the Apple developer account and the App Store release, so anyone can install it without a Mac.
>
> ### **→ [Support Reeb](https://dodo.pe/reeb)** · **[Join the waitlist](https://tally.so/r/44RV05)**

---

## Status: fully functional, not production ready

Read this before you build it.

Reeb works. I use it to record my own videos. But it was built fast, it has not been through App Store review, it has no test suite, and it has only ever run on one device (an iPhone 14, iOS 26). Expect rough edges. Voice tracking can lose you in a noisy room. The floating window behaves differently across iOS versions. Long scripts have not been stress tested.

**If you download and build this, you do so at your own risk.** There is no warranty of any kind, as spelled out in the [LICENSE](LICENSE). It touches your microphone, your camera and your photo library, so read the source before you run it. That is exactly why it is open.

I am actively improving it, and a free App Store release is planned. **Contributors are very welcome.** See [Contributing](#contributing) below.

---

## What it does

- **Voice-tracked scrolling** — the highlighted word follows your actual speech
- **Recovers from mistakes** — fumble a line, ad-lib, take a phone call; start reading again anywhere and it re-syncs within a few words
- **Records in-app** — camera inside the app puts the script right under the lens, video saves to Photos
- **Floating window** — Picture-in-Picture overlay for reading over other apps
- **Script library** — write, edit, duplicate, delete; everything stored on-device
- **Fully offline** — airplane mode changes nothing

## How it works

Two speech recognizers, no language model:

| | |
|---|---|
| **Fast ear** | Apple `SFSpeechRecognizer`, on-device streaming. Emits words as you say them and drives the scroll. |
| **Careful ear** | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (`ggml-tiny.en`, 31 MB, bundled) re-listens to the last few seconds every 3 s and nudges the position if the fast ear missed something. |

A matching algorithm decides where the words you spoke land in your script. Big jumps are expensive, small ones are cheap:

- **Next word / skip one** → matches on a single word (instant, the common case)
- **Jump ahead** → needs *two consecutive* words within a 10-word lookahead, so a repeated "the" can't teleport you
- **Lost for 6+ words** → searches the whole script for the last three words heard and jumps to where you actually are

Full write-up in [ARCHITECTURE.md](ARCHITECTURE.md), including the three walls hit along the way (black PiP frames, a tracker that died permanently, and why you can't float over Apple's Camera app).

## Source map

```
Reeb/
├── ReebApp.swift            App entry
├── ContentView.swift        Script library
├── ScriptEditorView.swift   Write / edit a script
├── ScriptStore.swift        Persistence (UserDefaults JSON)
├── PrompterView.swift       Full-screen prompter
├── RecordView.swift         In-app camera + script overlay
├── CameraRecorder.swift     AVCaptureSession + AVAssetWriter
├── SpeechTracker.swift      Recognition + the matching algorithm
├── WhisperVerifier.swift    whisper.cpp verification pass
├── AudioRingStore.swift     Rolling 8 s buffer @ 16 kHz mono
├── PipController.swift      Picture-in-Picture floating window
├── PipFrameRenderer.swift   Draws script text into video frames
└── SampleBufferLayerView.swift
```

## Get it on your iPhone

There are two ways, depending on whether you own a Mac.

### 👨‍💻 You have a Mac — build it yourself, today

You need Xcode, an iPhone and a cable. **A free Apple ID is enough**, the $99 developer program is not required.

```bash
git clone https://github.com/aiwithenoch/reebopensource.git
cd reebopensource
./scripts/download-model.sh   # fetches the Whisper model (31 MB)
open Reeb.xcodeproj
```

Then set your own team and a unique bundle identifier under **Signing & Capabilities**, turn on Developer Mode on the phone, and hit Run.

**→ [Full step-by-step guide in BUILD.md](BUILD.md)** — written for someone who has never opened Xcode, including every error you might hit and how to fix it.

Two things that trip people up: you must change the bundle identifier to your own, and apps signed with a free Apple ID **stop opening after 7 days** (plug in, press ⌘R, back in 30 seconds).

### 📱 No Mac — join the waitlist

Apple only allows installs from Xcode, TestFlight or the App Store, so without a Mac there is nothing to download yet. A free TestFlight build is planned, which will make it a two-tap install for anyone.

**→ [Join the waitlist](https://tally.so/r/44RV05)** and you get the link the day it opens.

## Requirements

- iOS 17+
- Xcode 16+
- iPhone with a microphone (the Simulator can't do speech input)

## Contributing

Contributions are genuinely wanted, whether that is a fix, a feature, better docs, or just a bug report from a device I do not own.

**Reporting something broken** is as useful as code. Open an issue with your iPhone model, iOS version, what you did, and what happened instead. "Voice tracking stopped after about a minute on an iPhone 12" is a great issue.

**Sending code:** fork the repo, make your change, and open a pull request explaining what it fixes and how you tested it on a real device. Keep pull requests focused on one thing. Match the existing style: plain SwiftUI, no new dependencies unless there is a strong reason, comments only where the code cannot explain itself.

**Good places to start**, roughly easiest first:

- Adjustable overlay position, size and opacity in the recorder
- A countdown before recording starts
- Import scripts from Files, Notes or the clipboard
- Landscape support for the prompter
- Larger Whisper models as an option for users who want accuracy over speed
- Multi-language recognition (the matcher normalizes with `isLetter`/`isNumber`, so it needs work for non-Latin scripts)
- Tests for the word matcher in `SpeechTracker.swift`, which is the piece most worth protecting

## Support this project

Reeb is free and stays free. If it saves you time, [chip in here](https://dodo.pe/reeb) — 17 people already have. It covers the Apple developer account and the App Store release, which is what lets people install it without owning a Mac.

Not able to? Starring the repo and sharing it helps just as much.

## Roadmap

- [ ] App Store release (free)
- [ ] Multi-language recognition
- [ ] Import scripts from Files / Notes
- [ ] Adjustable overlay position and opacity
- [ ] Countdown before recording

## License

MIT — see [LICENSE](LICENSE).

whisper.cpp is MIT licensed. The `ggml-tiny.en` model is released by OpenAI under MIT.
