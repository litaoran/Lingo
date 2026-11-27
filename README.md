# Lingo

**Private, on-device dictation for macOS that handles mixed Chinese and English.**

Hold a shortcut, speak, let go: Lingo transcribes on your Mac and pastes the text wherever your cursor is. Say "我们下周把这个 feature ship 出去" and you get exactly that, with Chinese kept as Chinese and English kept as English.

> 中文简介：Lingo 是一个开源的 macOS 口述输入工具，主打中英混说。按住快捷键说话，松开后在本机转写，并把文字粘贴到当前光标所在的 App。默认使用 Qwen3-ASR-1.7B（MLX），全部在本机运行，不上传任何音频或文字，也不收集任何统计数据。仅支持 Apple Silicon。

## Features

- **Global shortcuts.** Hold to talk (default <kbd>⌥ Space</kbd>), or press once to start and again to stop (default <kbd>⌥ ⇧ Space</kbd>). Both can be changed in Settings.
- **Pastes into any app.** The transcript goes to the app you're typing in. Your clipboard is put back afterwards.
- **Built for code-switching.** The default model, Qwen3-ASR-1.7B, keeps English words in English inside Chinese sentences.
- **Fully local.** Audio is recorded only while you dictate, transcribed on your Mac, and then discarded. No audio or text is uploaded and there is no analytics. The only network requests are model downloads from huggingface.co.
- **Switchable models.** Pick, download and delete models from the menu bar. Each model's size is shown before you download it.
- **Language setting.** Defaults to 中文 (Chinese), which handles mixed Chinese–English speech. English and Auto-detect are also available.

## Requirements

- A Mac with Apple Silicon (M1 or later). Intel Macs are not supported.
- macOS 14 Sonoma or later.
- About 2.5 GB of free disk space for the default model, and 8 GB of RAM or more.

## Install

1. Download `Lingo-<version>-arm64.dmg` from the [latest release](https://github.com/litaoran/Lingo/releases/latest).
2. Open the DMG and drag **Lingo** to **Applications**.
3. Open Lingo the first time (see below).

### Opening Lingo the first time

Lingo isn't signed with an Apple Developer ID yet, so macOS blocks it the first time you open it. Either:

- Open Lingo once. When macOS says it can't verify the app, go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the message about Lingo. Confirm with your password.
- Or remove the quarantine flag in Terminal:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Lingo.app
  ```

You only need to do this once per version.

### First launch

Lingo lives in the menu bar (microphone icon). On first launch it opens Settings with a short checklist:

1. **Download a model.** The default, Qwen3-ASR 1.7B (8-bit), is 2.47 GB.
2. **Allow microphone access.**
3. **Allow Accessibility access** so Lingo can paste for you.

Then hold <kbd>⌥ Space</kbd> anywhere, speak, and release.

## Permissions

| Permission | Why Lingo needs it | Without it |
|---|---|---|
| **Microphone** | To record while you hold or toggle the shortcut. Nothing is recorded at any other time. | Lingo can't dictate. |
| **Accessibility** | To press ⌘V in the app you're typing in. | The transcript is copied to the clipboard, and you paste it yourself. |

Lingo does not need Screen Recording, Input Monitoring or Full Disk Access.

**After updating Lingo:** because builds aren't signed with a Developer ID, macOS may keep an outdated Accessibility entry for the old version. If pasting stops working after an update, open **System Settings → Privacy & Security → Accessibility**, remove Lingo with **−**, and add it again.

## Models

Models are downloaded on demand from Hugging Face and stored in `~/Library/Application Support/Lingo/Models`. Switch, download or delete them from the menu bar (**Model ▸**) or from **Settings → Models**.

| Model | Download size | Notes |
|---|---|---|
| **Qwen3-ASR 1.7B, 8-bit** (default) | 2.47 GB | Best for mixed Chinese and English |
| Qwen3-ASR 1.7B, bf16 | 4.08 GB | Full precision; largest download and memory use |
| Qwen3-ASR 1.7B, 4-bit | 1.61 GB | Smaller and faster |
| Qwen3-ASR 0.6B, 8-bit | 1.01 GB | Smallest and fastest Qwen3-ASR |
| Whisper large-v3-turbo | 1.62 GB | Strong for English and many other languages |

Sizes are the files Lingo downloads. Qwen3-ASR weights come from [mlx-community](https://huggingface.co/mlx-community) and Whisper from [openai/whisper-large-v3-turbo](https://huggingface.co/openai/whisper-large-v3-turbo).

### Language setting

- **中文 (default):** for Chinese and mixed Chinese–English speech. English words and sentences stay in English.
- **English:** for English-only speech.
- **Auto-detect:** lets the model choose. With Qwen3-ASR, auto-detect may turn Chinese parts of mixed speech into English, which is why it isn't the default.

With Whisper, use **Auto-detect**: forcing 中文 makes Whisper translate English speech into Chinese.

## Benchmark

Why Qwen3-ASR-1.7B is the default: on bilingual Chinese–English recordings it was the most accurate open model tested. Scores are mixed error rate (MER); lower is better.

| Test set | Qwen3-ASR-1.7B | Whisper large-v3 |
|---|---|---|
| Personal bilingual recordings | **3.5%** | 7.0% |
| [ASCEND](https://huggingface.co/datasets/CAiRE/ASCEND) (Chinese–English code-switching) | **23–34%** | 35–44% |

## Build from source

Requirements: Xcode 26 or later, plus the Metal Toolchain component that MLX needs to compile its GPU kernels:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Then open `Lingo.xcodeproj` and run the **Lingo** scheme, or build a release DMG:

```bash
scripts/build-release.sh
```

MLX's Metal shaders can only be compiled by Xcode or `xcodebuild`; `swift build` doesn't work.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After editing `project.yml`, run `xcodegen generate`.

`mlx-audio-swift` is pinned to 0.1.4, the last release that builds with Swift 6.2 (Xcode 26.0–26.3). Newer releases need Swift 6.3.

### Command-line tool

The `lingo-cli` scheme builds a small tool that uses the same models and code as the app. It's handy for trying models or scoring them on your own test set:

```bash
lingo-cli list
lingo-cli download qwen3-asr-0.6b-8bit
lingo-cli transcribe --model qwen3-asr-1.7b-8bit --language zh recording.wav
lingo-cli bench --model qwen3-asr-1.7b-8bit --language zh --manifest clips.jsonl --out results.jsonl
```

Run it from the build products folder: it needs `mlx-swift_Cmlx.bundle` next to the binary.

## Privacy

- Audio stays in memory only while you dictate and is discarded after transcription. It's never written to disk.
- Transcripts are pasted, then forgotten. Lingo keeps only the most recent one in memory for **Copy Last Transcript**.
- No analytics, crash reporting or update checks. The only network traffic is model downloads from huggingface.co, which you start.
- Logs (viewable in Console.app under `io.github.litaoran.Lingo`) record timings and character counts, never transcript text.

## Acknowledgements

Lingo is built on [MLX](https://github.com/ml-explore/mlx-swift), [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts). It uses the [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) models (Apache-2.0) and [Whisper](https://github.com/openai/whisper) (MIT).

Thanks to the open-source dictation apps that explored this space first, including friday, MixDictate, qwen-dictation and [Hex](https://github.com/kitlangton/Hex).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency licenses.

## License

[MIT](LICENSE)
