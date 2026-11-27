# Lingo

**English** · [简体中文](README.zh-CN.md)

**Hold a key. Speak Chinese, English, or both. Get what you said, where your cursor is.**

Lingo is a dictation app for the Mac that does one thing: it turns mixed Chinese–English speech into text, on your Mac, and pastes it into whatever app you're typing in. Say "我们下周把这个 feature ship 出去" and you get exactly that: Chinese stays Chinese, English stays English.

Free and open source (MIT). Apple Silicon only.

## What it does

- **One shortcut.** Hold <kbd>⌥ Space</kbd>, speak, and let go to paste. For longer dictation, tap once to keep recording and tap again to finish. <kbd>Esc</kbd> cancels.
- **Gets mixed speech right.** The default model, Qwen3-ASR 1.7B, keeps English words in English inside Chinese sentences.
- **Spells your names and terms.** Add the names, products and jargon you use to the vocabulary list, and Lingo writes them the way you do.
- **Stays out of the way.** It ignores sound coming from your speakers, puts your clipboard back after pasting, and drops recordings that were only "嗯".
- **Never goes online.** Speech is transcribed on your Mac. Nothing is uploaded, and there are no accounts or analytics.

## What it doesn't do

Lingo stays small on purpose. It won't:

- rewrite, summarize or translate what you said
- use cloud models, accounts or subscriptions
- keep a history of what you dictated
- transcribe audio files or meetings

If you want those, [Hex](https://github.com/anomalyco/hex), [VoxtMini](https://github.com/hehehai/VoxtMini) and [VoiceInk](https://github.com/Beingpax/VoiceInk) are good open-source choices.

## Install

Requires a Mac with Apple Silicon (M1 or later) and macOS 14 Sonoma or later.

1. Download `Lingo-<version>-arm64.dmg` from the [latest release](https://github.com/litaoran/Lingo/releases/latest).
2. Open it and drag **Lingo** to **Applications**.
3. Open Lingo. It lives in the menu bar (microphone icon).

Releases are signed and notarized by Apple, so macOS opens them without warnings.

On first launch, Lingo walks you through three steps:

1. **Download the model** (2.47 GB, once).
2. **Allow microphone access**, so Lingo can hear you while you hold the shortcut.
3. **Allow Accessibility access**, so Lingo can paste for you. Without it, the text is copied and you paste it yourself.

Lingo doesn't need Screen Recording, Input Monitoring or Full Disk Access.

## Settings

Everything lives in **Settings** (menu bar icon → Settings…):

- **Shortcut:** change <kbd>⌥ Space</kbd> to any key combination.
- **Language:** 中文 (default) handles Chinese and mixed Chinese–English. Choose English if you only speak English.
- **Vocabulary:** names and terms you say often, separated by commas or new lines, for example `梓萱, Supabase, Kubernetes`. Words that sound the same are written your way too.
- **Model:** see below.

## Models

Models are downloaded from Hugging Face when you choose them and stored in `~/Library/Application Support/Lingo/Models`.

| Model | Download | Best for |
|---|---|---|
| **Qwen3-ASR 1.7B** (default) | 2.47 GB | Chinese and mixed Chinese–English |
| Qwen3-ASR 0.6B | 1.01 GB | Macs with 8 GB of memory |
| Whisper large-v3-turbo | 1.62 GB | Speech that is mostly English or another language |

With Whisper, set Language to Auto-detect: forcing 中文 makes Whisper translate English into Chinese. Whisper doesn't use the vocabulary list.

### Accuracy

On bilingual Chinese–English speech, Qwen3-ASR 1.7B was the most accurate open model tested. Scores are mixed error rate (MER); lower is better.

| Test set | Qwen3-ASR 1.7B | Whisper large-v3 |
|---|---|---|
| Personal bilingual recordings | **3.5%** | 7.0% |
| [ASCEND](https://huggingface.co/datasets/CAiRE/ASCEND) (Chinese–English code-switching) | **23–34%** | 35–44% |

## Privacy

- The microphone is on only while you dictate. Audio stays in memory and is discarded after transcription; it's never written to disk.
- Transcripts are pasted, then forgotten. Only the most recent one is kept in memory, for **Copy Last Transcript**.
- No analytics, crash reports or update checks. The only network requests are model downloads from huggingface.co, which you start.
- Logs (Console.app, `io.github.litaoran.Lingo`) record timings and lengths, never what you said.

## Updating

Download the new DMG and replace Lingo in Applications. Settings, models and permissions carry over. If you're coming from 0.1.0 and Lingo says Accessibility is off while System Settings shows it on, remove Lingo from **System Settings → Privacy & Security → Accessibility** with **−**, then turn it on again from Lingo.

## Building from source

See [BUILDING.md](BUILDING.md).

## Acknowledgements

Lingo is built on [MLX](https://github.com/ml-explore/mlx-swift), [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), and uses the [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) (Apache-2.0) and [Whisper](https://github.com/openai/whisper) (MIT) models.

Thanks to the open-source dictation apps that explored this space first, including [Hex](https://github.com/anomalyco/hex), [Handy](https://github.com/cjpais/Handy), [VoiceInk](https://github.com/Beingpax/VoiceInk), [Qwen Scribe](https://github.com/VladUZH/qwen-scribe) and [VoxtMini](https://github.com/hehehai/VoxtMini).

Dependency licenses are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE)
