# Mira for iOS

A voice assistant that runs your `mira.mdlo` model **entirely on the phone** —
no server, no API key, works in airplane mode. Speech recognition, generation,
and speech synthesis are all on-device.

## What it does

- Phone-call style conversation: tap to talk, Mira replies out loud
- Replies are spoken **sentence by sentence as they generate**, so she starts
  talking before the full answer exists — the same trick `voice/run_mira.py` uses
- Tap while she's talking to interrupt (normal call behavior)
- Speaks through a **Piper VITS voice** running on the phone via sherpa-onnx —
  not Apple's synthesizer. Falls back to `AVSpeechSynthesizer` when a build
  ships without the model
- Numbers are spoken as words ("fifteen to twenty minutes"), matching the
  training persona
- Conversation history is carried into every turn and trimmed to fit the context

## Repository layout

```
.github/workflows/build-ios.yml   builds an unsigned IPA on a macOS runner
ios/
  project.yml                     XcodeGen spec (no binary .xcodeproj in git)
  Mira/                           Swift sources + Info.plist
  Frameworks/                     llama + sherpa-onnx + onnxruntime, built by CI
  Resources/                      mira.mdlo, voice/, speech/ — fetched by CI
```

Neither `llama.xcframework` nor `mira.mdlo` is committed: the framework is
hundreds of megabytes of build output, and the model is far past GitHub's
100 MB file limit. Both are produced or fetched at build time, and both are
listed in `.gitignore`.

### The Swift sources

| File | Role |
|---|---|
| `MDLOFile.swift` | container parsing + checksum verification |
| `ModelLocator.swift` | finds the bundled or imported model |
| `LlamaEngine.swift` | llama.cpp wrapper, streaming generation |
| `Speech.swift` | speech-to-text, Apple text-to-speech, number spelling |
| `VoiceOutput.swift` | the voice protocol and its queue bookkeeping |
| `LocalVoice.swift` | on-device neural TTS through sherpa-onnx |
| `MiraFace.swift` | the mascot, drawn in a `Canvas` |
| `Motion.swift` | the shared animations |
| `CallViewModel.swift` | call state machine |
| `MiraApp.swift` | SwiftUI interface (`@main` lives here) |

## Building an IPA in CI (no Mac needed)

`.github/workflows/build-ios.yml` builds an **unsigned** `Mira-unsigned.ipa` on
a GitHub macOS runner. Run it from the Actions tab. It:

1. builds `llama.xcframework` from llama.cpp — only the `ios-device` and
   `ios-sim` slices, and cached between runs,
2. downloads `mira.mdlo` from your newest Release that has one attached,
3. generates the Xcode project with XcodeGen,
4. builds with signing disabled,
5. packages `Payload/Mira.app` into `Mira-unsigned.ipa`,
6. verifies the bundle really contains the binary, Info.plist, frameworks, and
   model,
7. attaches `Mira-unsigned.ipa` to the `ios-latest` prerelease, and also
   uploads it as a workflow artifact.

### Getting the .ipa itself

**Use the release, not the artifact.** `actions/upload-artifact` always zips
what it is given — there is no way to disable that — so downloading the
artifact gets you `Mira-unsigned-ipa.zip` with the `.ipa` inside, which
signing tools won't take and iOS Safari can't unwrap. Release assets are
served raw, so the `ios-latest` prerelease gives you a real `.ipa` you can
open straight into Sideloadly or AltStore, including on the phone itself.

It's a rolling tag: every successful build replaces the asset, so the link
never changes. Dispatch with `publish_release: false` to skip it.

Two workflow inputs:

- **`model_source`** — `latest-release` (default) bundles the model from your
  newest Release carrying a `mira.mdlo` asset; `none` builds without one, and
  you import a model in the app at runtime.
- **`publish_release`** — `true` (default) attaches the IPA to `ios-latest`;
  `false` builds the artifact only.
- **`bundle_tts`** — `true` (default) bundles the on-device voice and speech
  models, adding about 145 MB to the IPA. `false` builds without them and the
  app uses Apple's synthesizer and recognizer — much faster to iterate on.
- **`llama_ref`** — which llama.cpp commit to build against. The default is
  `master`. The app uses the current llama.cpp C API (`llama_model_load_from_file`,
  `llama_init_from_model`, `llama_memory_clear`, `llama_model_chat_template`),
  and that API does still change; **pin this to a release tag** once you have a
  build that works, so a later upstream rename can't break your next build.

**Note on macOS runners:** they cost **10× the minutes of Linux runners**. On a
public repo that's still free; on a private repo the first (uncached) build can
burn several hundred minutes of quota.

### Installing an unsigned IPA

Unsigned means iOS won't install it directly — you need to sign it with your own
identity first:

- **Sideloadly** or **AltStore** — sign with a free Apple ID (7-day expiry,
  renewable)
- **Apple Developer account** — sign for a full year
- **Xcode** — open the project and run to your device, which signs automatically

The CI build exists so the *compile* happens without a Mac; the *signing* still
needs your Apple ID somewhere.

## Building locally in Xcode

You need Xcode 15+ (iOS 17 SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

### 1. Build llama.cpp's xcframework

llama.cpp **no longer ships a Swift Package manifest**, so Swift Package Manager
won't work. Build its xcframework instead — the officially supported route:

```bash
git clone https://github.com/ggml-org/llama.cpp /tmp/llama.cpp
cd /tmp/llama.cpp
./build-xcframework.sh ios-device ios-sim
cp -R build-apple/llama.xcframework /path/to/this/repo/ios/Frameworks/
```

With no arguments the script builds all seven Apple platforms — macOS,
visionOS and tvOS included — one at a time. Naming the two iOS slices is
what keeps this to minutes rather than the better part of an hour.

While it runs it looks hung: each platform's output goes to its own
`build_<platform>.log` rather than the terminal, so the only thing printed
is one `Starting build:` line per platform. Because the script runs them
serially, that line appearing means the *previous* platform finished —
it is the progress bar. `tail -f build-apple/build_ios_device.log` shows
the live compile.

### 2. Generate and open the project

```bash
cd ios
xcodegen generate
open Mira.xcodeproj
```

`project.yml` already wires up the permission strings, the embedded
xcframework, and the iOS 17 deployment target — there is nothing to configure by
hand.

### 3. Run on a real device

Use a **real device**, not the simulator — the simulator's microphone and CPU
performance aren't representative, and llama.cpp is built for arm64.

### 4. Bundle the model into the app (recommended)

Ship the model inside the app so it works the instant it launches — no file
picker, no setup: drop `mira.mdlo` into `ios/Resources/` before generating the
project, and XcodeGen adds it to the app's Copy Bundle Resources phase.

The filename must be exactly `mira.mdlo`. On launch the app finds it, verifies
the checksum once, extracts the GGUF into Application Support, and reuses that
cache on later launches.

**Disk cost:** the model exists twice — once in the app bundle (read-only, can't
be memory-mapped from an offset) and once as the extracted GGUF. A 250 MB model
therefore uses about 500 MB. Settings ▸ *Free extracted cache* reclaims half of
that at the cost of re-extracting on next launch.

**App size:** a 250 MB bundled model is fine for personal builds and TestFlight.
For the App Store, consider **On-Demand Resources** or downloading the model on
first launch instead, so the initial install stays small.

### Which model files work

Both `.gguf` and `.mdlo` open, decided by the file's magic bytes rather than
its extension:

- **`.gguf`** — what every quantiser emits (`Q8_0`, `Q4_K_M`, and so on). It is
  used straight off disk, so unlike the container it costs no second copy.
  Carrying no prompt or sampling settings of its own, it gets Mira's defaults.
- **`.mdlo`** — the container from `voice/package_mdlo.py`, which carries a
  system prompt, sampling settings and a checksum alongside the weights.

Imported models keep their own filename in Documents, so several
quantisations can sit side by side and the newest one wins. The name is also
where the model summary comes from: `mira-Q8_0.gguf` shows as `mira · Q8_0`.

### Swapping models without rebuilding

Settings ▸ *Replace with a different model…* imports a `.mdlo` from Files. An
imported model wins over the bundled one only if it's newer, so shipping an
updated app won't be shadowed by a stale import. *Remove imported model* falls
back to the bundled one.

## Permissions

Both usage strings already live in `ios/Mira/Info.plist`:

| Key | Why |
|---|---|
| `NSMicrophoneUsageDescription` | Mira listens to your voice so you can talk to her. |
| `NSSpeechRecognitionUsageDescription` | Your speech is turned into text on this device so Mira can respond. |

`UIBackgroundModes ▸ audio` is enabled so Mira keeps talking when the screen
locks.

## Mira, and the app icon

She is one pastel hue in three steps — a near-white lit side, the pastel
itself, and a deeper shade for hair and the shadow it casts — rather than a
blend of colours. That restraint is most of what makes her look designed. The
hue comes from `Theme`, so picking a scheme in onboarding recolours her.

The silhouette is three low harmonics summed around a circle, each drifting at
its own rate so it never visibly repeats. Low harmonics on purpose: a high one
puts many small lobes around the rim, and small lobes read as points.

Hair is a solid hairline across the top with soft spikes rising out of it.
Both halves are needed. Spikes alone read as spikes; a band alone reads as a
swim cap. The spikes are narrow relative to their spacing so their tips stay
separate, and their tips are blunted — two curves meeting at a point give a
thorn, carrying the tip across a short flat between them gives hair.

The app icon is the same mascot, and `tools/make_icon.py` redraws it from the
same constants rather than tracing a screenshot:

    python3 tools/make_icon.py     # needs pillow

It writes the single 1024x1024 image iOS 17 derives the rest from. Change
`MiraFace.swift` and it is worth re-running; the two are meant to match.

One thing to know if you edit it: everything soft in that script is a blurred
`L` mask with a uniform colour poured through it, never a blurred RGBA layer.
PIL blurs colour channels independently of alpha, so blurring a transparent
layer drags RGB out of the transparent-black pixels around the shape — which
showed up as grey scratches across her.

## The voice

Apple's built-in voices are the compact ones unless you have downloaded better
ones, and they sound it. Mira instead runs a neural voice locally through
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) — far more natural, and
still no network.

The bundled model is `vits-piper-en_US-libritts_r-medium`: a Piper VITS voice
fine-tuned from `lessac-medium` on LibriTTS-R, 904 speakers at 22.05 kHz.

| Part | Size |
|---|---|
| `model.onnx` | 75 MB |
| `espeak-ng-data/` | 0.9 MB |
| `tokens.txt` | 1 KB |

This replaced **Kokoro-82M**, which sounded a little better and cost far too
much for it — 110 MB of int8 weights, a 52 MB voice bank and a 5.7 MB lexicon,
185 MB in all. The size was the smaller problem. Kokoro is 82 M parameters of
transformer to run before the first sample exists, so there was an audible beat
between Mira finishing thinking and starting to talk. A Piper medium model is a
fraction of that to run, which is what closes the gap.

`espeak-ng-data` ships one pronunciation dictionary per language, and those are
17 MB of its 19 MB. espeak only ever opens the dictionary for the language it
is asked for, so CI keeps `en_dict` and deletes the rest — 19 MB to under 1 MB
with nothing lost for an English voice. It is copied in as a **folder
reference** so its directory structure survives into the bundle; the engine
reads it by path.

Sentences are synthesized one at a time on a background actor while the LLM
generates the next one, peak-normalised so the level is consistent, and played
through an `AVAudioPlayerNode`.

`LocalVoice.speakerID` picks which of the 904 speakers to use, clamped to what
the loaded model actually has. Settings ▸ *Voice* offers the first six and
shows which engine loaded, which is the quickest way to confirm the model made
it into the build.

## Speech to text

Builds that bundle the models use a **streaming Zipformer transducer** through
sherpa-onnx rather than `SFSpeechRecognizer`. Three reasons:

- It is genuinely on-device. Apple's recognizer silently falls back to its
  *server* recognizer when the offline asset for the locale isn't installed,
  which broke airplane mode without saying so.
- It doesn't need Dictation enabled, which was a real failure mode.
- It emits a continuously growing transcript rather than chunked partials,
  which is what makes the live transcription read as live.

It also endpoints for itself — the model decides when you have stopped
speaking — replacing the hand-rolled silence timers that caused the early
"the button switches on and straight back off" bug. The timers remain only as
a backstop.

The model is `sherpa-onnx-streaming-zipformer-en-2023-06-26`. The 20 M
parameter recipe was tried in its place — a third of the encoder compute and
26 MB smaller — and its transcription was not good enough to keep.

Only the int8 weights are bundled: the float encoder alone is 249 MB against
67 MB quantized, for about 68 MB total. `SFSpeechRecognizer` stays as the
fallback for builds made with `bundle_tts: false`.

`StreamingRecognizer` leaves `model_type` empty so sherpa-onnx reads the
architecture out of the encoder's own ONNX metadata. Hardcoding it means
keeping the value in sync with whatever CI downloads, and getting it wrong
fails at load — the 20 M model is a `zipformer` and this one a `zipformer2`,
so the value had to change with the download and now does not.

## Performance notes

A 360M Q4_K_M model on an A16 or newer generates faster than speech, so Mira
answers with no perceptible lag. Expect roughly 250 MB of RAM while loaded.
Larger models (1–2 B) work but load slower and use proportionally more memory —
on older devices, prefer 360M–0.5B.

## Troubleshooting

**The file picker shows `mira.mdlo` greyed out** — you're on a build from
before the `.mdlo` document type was declared in `Info.plist`. Rebuild. Two
other ways in on a current build: put the file in **Files ▸ On My iPhone ▸
Mira** and reopen the app, or share it to Mira from the Files share sheet.

**The talk button switches on and straight back off** — fixed; rebuild. An
early empty recognition result was collapsing the opening window down to the
1.1 s end-of-turn pause, ending the turn about a second after the tap. The
short window now applies only once something has actually been transcribed;
until then you get `SpeechListener.openingSilence` (6 s) to start speaking.

**Tapping to talk never ends the turn** — also fixed by rebuilding: the turn
used to end only on a recognition result, so silence left it listening
indefinitely.

**"Speech recognition isn't available right now"** — dictation is off. Settings
▸ General ▸ Keyboard ▸ Enable Dictation. Speech-to-text runs on-device when the
device supports it for your locale; otherwise iOS falls back to its server
recognizer, which needs a network connection.

**"That file isn't an MDLO model"** — you picked the GGUF instead of the
`.mdlo`, or the download was incomplete.

**"The model file is corrupt"** — the checksum didn't match; re-download the
Release artifact.

**Mira answers but says nothing** — check the silent switch, and confirm a
system voice is installed under Settings ▸ Accessibility ▸ Spoken Content.

**Speech recognition never finishes a turn** — `SpeechListener.endOfTurnSilence`
(default 1.1 s) controls how long a pause ends your turn; raise it if you speak
with long pauses.

**The build fails on a missing llama.cpp symbol** — llama.cpp renamed something
on `master`. Re-run the workflow with `llama_ref` set to a release tag from
before the rename, or update the call sites in `LlamaEngine.swift`.
