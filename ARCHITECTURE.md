# Architecture

Reeb is a SwiftUI app with no backend, no accounts, and no network calls. Everything — including both speech engines — runs on the phone.

## The pipeline

```
microphone (or camera audio)
        │
        ├──────────────► SFSpeechRecognizer ──► words, streaming, ~instant
        │                                            │
        └──► AudioRingStore (8 s @ 16 kHz) ──► whisper.cpp every 3 s
                                                     │
                                          ┌──────────┴──────────┐
                                          ▼                     ▼
                                    word matcher  ──►  script position
                                                              │
                                              ┌───────────────┼───────────────┐
                                              ▼               ▼               ▼
                                        PrompterView    RecordView     PiP window
```

## Why two recognizers

Apple's on-device recognizer is the best *streaming* option on an iPhone — it emits words within milliseconds, which is what a teleprompter needs. But it drops words on accents, mumbles, and noise.

Whisper is more accurate but processes in chunks, so it lags 1–3 seconds behind. Alone it would feel drunk.

Running both: Apple drives the scroll in real time, Whisper quietly corrects it. The verification pass requires **three consecutive script words** to agree before it moves anything, so ambient noise can never shift the script.

There is **no language model here.** Both engines are speech recognizers — audio in, text out. The behavior that feels intelligent (recovering after a mistake, ignoring off-script talk, refusing to jump on repeated words) is the matching algorithm below. A local LLM would add gigabytes and hundreds of milliseconds to something that has to react instantly, and it isn't needed: nothing in this problem requires language *understanding*, only "did they say these words, and where in the script are they?"

## The matching algorithm

`SpeechTracker.advance(with:)` — the heart of the app. Every spoken word is normalized (lowercased, punctuation stripped) and tested against the script:

| Case | Requirement | Why |
|---|---|---|
| Next word | 1 word | The common case. Must be instant. |
| Skip one word | 1 word | Absorbs a mumble or a dropped word. |
| Jump ≤10 words ahead | 2 consecutive words | Stops repeated words ("the", "and") from teleporting the reader. |
| Lost ≥6 words | 3 consecutive words, searched across the entire script | Re-sync after a mistake, an ad-lib, or a skipped paragraph. |

The last row is what makes it usable on a real shoot. You can stop mid-sentence, talk to someone for a minute, then resume at any line — it finds you.

## Keeping the microphone alive

Recognition dies constantly in normal use: iOS finalizes a session after silence, other apps grab the mic, audio routes change when headphones connect. Three defenses:

1. **Auto-restart on finalize** — when iOS ends an utterance, a fresh session starts immediately.
2. **Generation counter** — each session gets an ID; callbacks from cancelled sessions are ignored, so a stale error can't fight the restart logic.
3. **Watchdog** — every 2 seconds, verify the audio engine is actually running and revive it if not.

A hard-won detail: once listening has succeeded at least once, later failures **must not** set the tracker to an error state. An early version did, and because the watchdog only revived trackers that were still "listening," a single mic hiccup killed tracking permanently — the dead state was unreachable by the thing designed to save it.

## The floating window (Picture-in-Picture)

`PipController` + `PipFrameRenderer` render the script into video frames and feed them to an `AVSampleBufferDisplayLayer` that iOS floats above other apps.

Two non-obvious requirements:

- **The layer needs a running `controlTimebase`.** Without it, frames are accepted and never displayed — the window is simply black. Create the timebase from the host time clock, set rate to `1.0`, and stamp every frame with `CMTimebaseGetTime`.
- **The layer must be on screen** in the presenting view for PiP to start, and it needs a *continuous* feed (a timer pushes frames at 4 fps) or the window won't stay alive.

`requiresLinearPlayback = false` turns on the skip buttons inside the floating window, which are remapped to "jump 8 words back / forward."

## Why the camera lives inside the app

The original goal was a script floating over Apple's Camera app. iOS won't allow it:

1. Opening Camera claims the microphone, which tears down the background audio session, which suspends the app — and the floating window with it.
2. Even when the window survives, **recording holds the mic exclusively.** Nothing else can listen. Voice tracking would freeze exactly when it's needed.

This is platform policy, not a bug to code around. The fix is to own the whole pipeline: `CameraRecorder` runs a single `AVCaptureSession` with both video and audio inputs, writes to `AVAssetWriter`, and **forks every audio buffer two ways** — into the video file, and into `SpeechTracker.ingest(_:)` for recognition. One app, one microphone, no contention.

When the tracker is fed this way (`start(externalAudio: true)`) it skips its own `AVAudioEngine` entirely and appends camera buffers directly to the recognition request.

## Threading

- **Capture queue** — camera buffers arrive here; forked to the writer and to recognition
- **Audio tap thread** — mic buffers; writes into `AudioRingStore` behind an `NSLock`
- **Whisper queue** — transcription runs at `.userInitiated`, one pass at a time
- **Main actor** — `SpeechTracker` state and all UI

`AudioRingStore` and the recognition-request handle are `@unchecked Sendable` boxes with explicit locking, because audio callbacks can't hop actors without dropping frames.

## Performance

- **Release builds only** for real use. In debug, Whisper runs several times slower — enough to feel it.
- **Row layout is cached** (`buildRows()` once on load) rather than recomputed per word, which matters on long scripts.
- **Scroll animation is 150 ms.** Slower feels laggy; faster feels jumpy.
