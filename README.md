# Reeb

A teleprompter for iOS that scrolls **because you're talking** — not because a timer said so.

Read, and the script moves. Pause, and it waits. Go off-script, and it holds your place until you come back. Speech recognition runs entirely on the phone: no account, no API key, no server, no subscription.

Built with [Claude Code](https://claude.com/claude-code) in an afternoon. Open sourced so you can build your own.

📱 [Demo on TikTok](https://www.tiktok.com/@aiwithenoch/video/7668759110187273490)

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

## Build it

You need a Mac with Xcode, an iPhone, and a cable. **A free Apple ID is enough** — the $99 developer program is not required.

```bash
git clone https://github.com/aiwithenoch/reebopensource.git
cd reebopensource
./scripts/download-model.sh
open Reeb.xcodeproj
```

Then in Xcode: select your device, set your own team under **Signing & Capabilities**, change the bundle identifier to something unique, and hit Run.

**One-time phone setup:** plug in and tap Trust → Xcode → Settings → Accounts → add your Apple ID → on the phone, Settings → Privacy & Security → **Developer Mode** → on → restart.

### Heads up: the day-8 surprise

Apps signed with a free Apple ID **stop opening after 7 days**. Nothing is broken — plug the phone in and reinstall (about 30 seconds). A paid developer account extends this to a year.

## Requirements

- iOS 17+
- Xcode 16+
- iPhone with a microphone (the Simulator can't do speech input)

## Prompts

The exact prompts used to build this — typos and all — are in [PROMPTS.md](PROMPTS.md). They're unedited on purpose: you don't need clean prompts, you need clear intent and honest feedback about what's broken.

## Roadmap

- [ ] App Store release (free)
- [ ] Multi-language recognition
- [ ] Import scripts from Files / Notes
- [ ] Adjustable overlay position and opacity
- [ ] Countdown before recording

## License

MIT — see [LICENSE](LICENSE).

whisper.cpp is MIT licensed. The `ggml-tiny.en` model is released by OpenAI under MIT.
