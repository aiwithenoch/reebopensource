# Build Reeb and run it on your iPhone

A complete walkthrough, written for someone who has never opened Xcode. About 20 minutes, most of it waiting for downloads.

**You do not need a paid Apple Developer account.** A free Apple ID is enough.

Stuck at any step? [Open an issue](https://github.com/aiwithenoch/reebopensource/issues) with what you tried and the exact error, and it will get answered.

---

## What you need

| | |
|---|---|
| **A Mac** | Any Mac that runs Xcode 16. There is no way around this one, Apple only allows apps to be installed from Xcode, TestFlight or the App Store. |
| **Xcode 16 or later** | Free from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835). It is a large download, around 10 GB, so start it first. |
| **An iPhone running iOS 17 or later** | The Simulator cannot do speech input, so a real device is required. |
| **A USB cable** | For the first install. After that you can switch to wireless. |
| **An Apple ID** | The one you already use. Free is fine. |

---

## Step 1 — Get the code

```bash
git clone https://github.com/aiwithenoch/reebopensource.git
cd reebopensource
```

## Step 2 — Download the Whisper model

The app bundles an open source Whisper model, about 31 MB. It is not committed to the repo, so fetch it once:

```bash
./scripts/download-model.sh
```

You should end up with `Reeb/ggml-tiny.en-q5_1.bin`. **The build will fail without it**, so do not skip this.

## Step 3 — Open the project

```bash
open Reeb.xcodeproj
```

Xcode will resolve the Swift package dependency ([SwiftWhisper](https://github.com/exPHAT/SwiftWhisper)) on first open. Give it a minute. If it seems stuck, use **File → Packages → Resolve Package Versions**.

## Step 4 — Sign in to Xcode

**Xcode → Settings → Accounts → ＋ → Apple Account**, then sign in.

This is what lets Xcode sign the app so your iPhone will trust it. Your Apple ID stays on your machine.

## Step 5 — Set your own team and bundle ID

Click the blue **Reeb** project in the left sidebar, select the **Reeb** target, then the **Signing & Capabilities** tab.

1. **Team** — pick your own name, shown as *(Personal Team)*
2. **Bundle Identifier** — change it to something unique to you, for example `com.yourname.reeb`

> **The bundle identifier must be changed.** `com.aiwithenoch.reeb` is already registered to someone else, and signing fails with *"Failed to register bundle identifier"* until you use your own.

Xcode creates a provisioning profile automatically once both are set. You should see a green tick and no red text.

## Step 6 — Turn on Developer Mode on the iPhone

Plug the phone in and tap **Trust** if it asks.

On the iPhone: **Settings → Privacy & Security → Developer Mode → on**, then restart the phone. After it reboots, unlock it and tap **Turn On** when prompted.

Developer Mode only appears in Settings after a Mac with Xcode has connected to the phone at least once. If you cannot find it, plug in, open Xcode, and look again.

## Step 7 — Build and run

Pick your iPhone from the device menu at the top of the Xcode window, then press **⌘R**.

First build takes a few minutes because whisper.cpp compiles from source. Later builds are much faster.

## Step 8 — Trust the developer certificate

The first launch will fail with **"Untrusted Developer"**. This is normal.

On the iPhone: **Settings → General → VPN & Device Management → [your Apple ID] → Trust**.

Open Reeb again and it will launch.

## Step 9 — Grant permissions

On first run Reeb asks for the **microphone** and **speech recognition**, and for the **camera** and **Photos** when you first record. All processing is local, nothing is uploaded, and you can read exactly what it does with them in the source.

---

## Building from the command line

If you would rather not use the Xcode interface:

```bash
# Find your device's identifier
xcrun devicectl list devices

# Build a release version
xcodebuild -project Reeb.xcodeproj -scheme Reeb \
  -configuration Release \
  -destination 'platform=iOS,id=YOUR_DEVICE_ID' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  PRODUCT_BUNDLE_IDENTIFIER=com.yourname.reeb \
  build

# Install it
xcrun devicectl device install app --device YOUR_DEVICE_ID \
  ~/Library/Developer/Xcode/DerivedData/Reeb-*/Build/Products/Release-iphoneos/Reeb.app
```

Your team ID is in **Xcode → Settings → Accounts → Manage Certificates**, or in `~/Library/Preferences/com.apple.dt.Xcode.plist`.

**Always build Release for real use.** In a Debug build the compiler optimisations are off and Whisper runs several times slower, which is noticeable while recording.

---

## The 7 day expiry

Apps signed with a free Apple ID **stop opening after 7 days**. Nothing is broken and your scripts are safe.

To fix it, plug the phone in and press **⌘R** again. It takes about 30 seconds.

A paid Apple Developer Program membership at $99 a year extends this to a year. A hosted [TestFlight](https://developer.apple.com/testflight/) build is planned so that most people will not have to build anything at all — [join the waitlist](https://tally.so/r/44RV05) to get that link when it opens.

---

## When something goes wrong

**"Failed to register bundle identifier"**
Someone already owns that identifier. Go back to step 5 and pick your own.

**"No account for team" or "no signing certificate"**
Xcode has no Apple ID. Step 4.

**"Developer Mode disabled"**
Step 6, and remember it needs a restart to take effect.

**Build fails on a missing `ggml-tiny.en-q5_1.bin`**
Step 2, the model was never downloaded.

**Package resolution fails or hangs**
Check your network, then **File → Packages → Reset Package Caches**. If it still fails:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Reeb-*/SourcePackages
```

**Speech recognition never starts**
Confirm the microphone and speech permissions were allowed in **Settings → Reeb**. Also check you are on a real iPhone, since the Simulator has no microphone input.

**Voice tracking feels inaccurate**
The bundled model is `tiny.en`, the smallest and least accurate size, chosen to keep the app small. Swapping in a larger model such as `small.en` improves accuracy noticeably at the cost of about 466 MB. See [ARCHITECTURE.md](ARCHITECTURE.md).

---

## What to read next

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the two speech engines work together, the word matching algorithm, and the three problems that were hardest to solve
- [README.md](README.md) — what the app does and where each source file lives

Contributions are welcome. Bug reports from devices other than an iPhone 14 are genuinely useful, since that is the only hardware this has been tested on.
