# Building Lingo

## Requirements

- A Mac with Apple Silicon
- Xcode 26 or later
- The Metal Toolchain component, which MLX needs to compile its GPU kernels:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Build

Open `Lingo.xcodeproj` and run the **Lingo** scheme, or build a DMG:

```bash
scripts/build-release.sh
```

Local builds are ad-hoc signed. macOS ties permissions to the signature, so after each rebuild you may need to switch Accessibility off and on again for Lingo.

To produce a signed and notarized release, pass your Developer ID and a notarytool keychain profile (created once with `xcrun notarytool store-credentials`):

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=lingo-notary scripts/build-release.sh
```

Notes:

- MLX's Metal shaders can only be compiled by Xcode or `xcodebuild`; `swift build` doesn't work.
- The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After editing `project.yml`, run `xcodegen generate`.
- `mlx-audio-swift` is pinned to 0.1.4, the last release that builds with Swift 6.2 (Xcode 26.0–26.3). Newer releases need Swift 6.3.

## Command-line tool

The `lingo-cli` scheme builds a small tool that uses the same models and code as the app. It's handy for trying models or scoring them on your own test set:

```bash
lingo-cli list
lingo-cli download qwen3-asr-0.6b-8bit
lingo-cli transcribe --model qwen3-asr-1.7b-8bit --language zh --vocabulary "梓萱, Supabase" recording.wav
lingo-cli bench --model qwen3-asr-1.7b-8bit --language zh --manifest clips.jsonl --out results.jsonl
```

Run it from the build products folder: it needs `mlx-swift_Cmlx.bundle` next to the binary.

## Self-tests

The app has two self-test modes, launched through `open` so macOS applies Lingo's own microphone permission:

```bash
open -n -W Lingo.app --args --self-test <audio-file> [model-ids...]
open -n -W Lingo.app --args --self-test record <seconds> <on|off> <out-file> [prewarm]
```

The second records from the microphone with echo cancellation on or off and writes one JSON line with the transcript and startup timings.
