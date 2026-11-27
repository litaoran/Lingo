# Lingo

[English](README.md) · **简体中文**

**按住说话，松开出字。中英混着说，原样打出来。**

Lingo 是一个 Mac 上的语音输入工具，只做一件事：把你中英混说的话在本机转成文字，粘贴到你正在打字的 App 里。说“我们下周把这个 feature ship 出去”，打出来的就是这句话：中文是中文，英文是英文。

免费开源（MIT），仅支持 Apple Silicon。

## 它做什么

- **一个快捷键。** 按住 <kbd>⌥ Space</kbd> 说话，松开就粘贴。要说长一点，点一下开始、再点一下结束。<kbd>Esc</kbd> 取消。
- **中英混说也准。** 默认模型 Qwen3-ASR 1.7B 会让中文句子里的英文单词保持英文。
- **认得你常用的名字和术语。** 把人名、产品名、行话加进热词表，Lingo 就按你的写法打出来。
- **不打扰你。** 不会把扬声器里放的声音录进去，粘贴后把剪贴板恢复原样，只说了一声“嗯”的录音直接丢弃。
- **完全不联网。** 在你的 Mac 上转写，什么都不上传，不用注册账号，也没有任何统计。

## 它不做什么

Lingo 有意保持简单，不会：

- 改写、总结或翻译你说的话
- 用云端模型、要你注册账号或订阅
- 保存你说过的内容
- 转写音频文件或会议录音

需要这些功能的话，[Hex](https://github.com/anomalyco/hex)、[VoxtMini](https://github.com/hehehai/VoxtMini) 和 [VoiceInk](https://github.com/Beingpax/VoiceInk) 都是不错的开源选择。

## 安装

需要 Apple Silicon（M1 或更新）的 Mac，以及 macOS 14 Sonoma 或更新版本。

1. 从 [最新版本](https://github.com/litaoran/Lingo/releases/latest) 下载 `Lingo-<版本号>-arm64.dmg`。
2. 打开 DMG，把 **Lingo** 拖进 **应用程序**。
3. 打开 Lingo，它在菜单栏里（麦克风图标）。

发布版已经过 Apple 签名和公证，打开时不会有安全警告。

第一次打开时，Lingo 会带你完成三步：

1. **下载模型**（2.47 GB，只需一次）。
2. **允许使用麦克风**，这样按住快捷键时 Lingo 才能听到你。
3. **允许辅助功能权限**，这样 Lingo 才能帮你粘贴。不开的话，文字会复制到剪贴板，需要你自己粘贴。

Lingo 不需要屏幕录制、输入监控或完全磁盘访问权限。

## 设置

所有设置都在 **Settings**（菜单栏图标 → Settings…）里：

- **快捷键：** 可以把 <kbd>⌥ Space</kbd> 换成任何组合键。
- **语言：** 默认 中文，适合中文和中英混说。只说英文的话选 English。
- **热词表（Vocabulary）：** 你常说的名字和术语，用逗号或换行分隔，比如 `梓萱, Supabase, Kubernetes`。读音相同的词也会按你的写法打出来。
- **模型：** 见下文。

## 模型

模型在你选择时从 Hugging Face 下载，存放在 `~/Library/Application Support/Lingo/Models`。

| 模型 | 下载大小 | 适合 |
|---|---|---|
| **Qwen3-ASR 1.7B**（默认） | 2.47 GB | 中文和中英混说 |
| Qwen3-ASR 0.6B | 1.01 GB | 8 GB 内存的 Mac |
| Whisper large-v3-turbo | 1.62 GB | 以英文或其他语言为主 |

使用 Whisper 时请把语言设为 Auto-detect：强制设为中文会让 Whisper 把英文翻译成中文。Whisper 不使用热词表。

### 准确率

在中英双语语音上，Qwen3-ASR 1.7B 是测试过的开源模型里最准的。指标是混合错误率（MER），越低越好。

| 测试集 | Qwen3-ASR 1.7B | Whisper large-v3 |
|---|---|---|
| 个人中英双语录音 | **3.5%** | 7.0% |
| [ASCEND](https://huggingface.co/datasets/CAiRE/ASCEND)（中英混说） | **23–34%** | 35–44% |

## 隐私

- 只有你在说话时麦克风才会打开。音频只存在内存里，转写完就丢弃，从不写入磁盘。
- 文字粘贴之后就不再保留。内存里只留最近一条，用于 **Copy Last Transcript**。
- 没有统计、崩溃报告或更新检查。唯一的网络请求是你手动发起的、从 huggingface.co 下载模型。
- 日志（在“控制台”App 里搜 `io.github.litaoran.Lingo`）只记录耗时和长度，从不记录你说了什么。

## 更新

下载新的 DMG，替换掉“应用程序”里的 Lingo 即可，设置、模型和权限都会保留。如果你是从 0.1.0 升级，并且 Lingo 提示辅助功能未开启、但系统设置里显示已开启：在 **系统设置 → 隐私与安全性 → 辅助功能** 里用 **−** 删除 Lingo，再从 Lingo 里重新开启。

## 从源码构建

见 [BUILDING.md](BUILDING.md)（英文）。

## 致谢

Lingo 基于 [MLX](https://github.com/ml-explore/mlx-swift)、[mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) 和 [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)，使用 [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR)（Apache-2.0）和 [Whisper](https://github.com/openai/whisper)（MIT）模型。

感谢先在这个领域探索的开源语音输入项目，包括 [Hex](https://github.com/anomalyco/hex)、[Handy](https://github.com/cjpais/Handy)、[VoiceInk](https://github.com/Beingpax/VoiceInk)、[Qwen Scribe](https://github.com/VladUZH/qwen-scribe) 和 [VoxtMini](https://github.com/hehehai/VoxtMini)。

依赖库的许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可证

[MIT](LICENSE)
