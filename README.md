# Muxie

一个简洁的原生 Mac 轨道整理工具。SwiftUI + 系统 Liquid Glass，最低目标 macOS 26，当前自用构建为 Apple Silicon（arm64）。

## 已实现

- 导入 MP4 / MKV，识别视频、音频、字幕轨道。
- 添加外部音轨，在播放器中作为独立音轨切换，不混音。
- 添加 SRT 字幕；取消勾选即从新的 MKV 中移除不需要的音轨或字幕。
- 修改轨道显示名称、语言、默认轨道和字幕强制标记。
- MP4 → MKV 无损重新封装，不进行视频/音频重新编码。
- 导出进度、取消、失败清理、成品轨道校验、拒绝覆盖输入及已有输出。
- 本机处理，无账户、无上传、无遥测。只在用户点击官网链接时打开网站。

## 使用

1. 将 DMG 中的 Muxie 拖入 Applications，然后启动。
2. 选择主影片，或把影片拖进窗口。
3. 点“添加音轨 / 字幕”，选择独立音频、SRT 或另一部包含所需轨道的影片。
4. 勾选需要保留的轨道，点选轨道，在右边编辑显示名称和语言。
5. 点“导出 MKV”，使用新的文件名。不会修改原影片。

字幕是可切换的软字幕，不是烧进画面。已烧入画面的字幕不能移除。播放器可能优先采用自身的语言偏好，因此默认标志不保证自动选中。不会转码、混音、修复音画不同步或处理 DRM。输入兼容性由 MKVToolNix 决定。

附件/章节策略：保留主来源章节、全局标签及附件；从附加来源导入字幕时也保留该来源附件（例如 ASS 字体）。不合并附加来源的章节和全局标签。

## 构建

安装 Xcode（包含 macOS 26 或更新 SDK）。双击 `Package.swift` 可在 Xcode 浏览源码。可安装的 app 用以下脚本构建：

```sh
chmod +x build.sh test.sh
./build.sh
./package-dmg.sh
```

默认生成 `dist/Muxie.app`，不含第三方引擎。它会查找 `/Applications/MKVToolNix.app`、用户 Applications、Homebrew，或者“关于 Muxie”中选取的 mkvmerge。自定义路径优先于内置引擎。已有输出目录不会被静默删除，重复构建请先移动旧 app，或设置新的 `OUT_DIR`。

本机自用、复制已安装官方 app 的引擎（当前验证的是 MKVToolNix 103.0 / Qt Core 6.11.1）：

```sh
./build.sh --bundle-installed-engine
```

这是本地开发构建，采用 ad-hoc 签名，没有 Developer ID 公证，也没有自动更新。本脚本只清理新装配开发包继承的 quarantine 标记，不修改系统保护设置或原来的 MKVToolNix 安装。对外发放之前，需要正式处理签名、公证和许可证合规，而不是直接发布这个自用 DMG。

## 测试

```sh
# 仅生成测试素材时需要 ffmpeg，应用运行不需要它。
./test.sh
```

2026-11-08 在当前 Mac（macOS 27.3、Apple Silicon、SDK 27.2）上完成 14 项检查，覆盖双音轨、双字幕、中英文名称、语言、默认标志、删除轨道、MP4 重封装、覆盖保护、取消及进度解析；并通过真实界面导出。输出样本的视频和音频编码数据 SHA-256 均与输入一致。详见 `TESTING.md`。未在独立 macOS 26 设备或 Intel Mac 上实机验证。

## 开源与第三方

Muxie 自有源码和图标采用 **GPL-2.0-only**，见 `LICENSE`。

本应用是独立原生前端，不是 MKVToolNix 官方产品，也没有复制其 GUI 代码。媒体处理由独立进程 `mkvmerge` 完成。感谢 Moritz Bunkus 及 MKVToolNix 贡献者。

- 官方网站：https://mkvtoolnix.download/
- 上游源码：https://codeberg.org/mbunkus/mkvtoolnix
- MKVToolNix：GPL-2.0-only。
- 源码压缩包不含 mkvmerge 或 Qt 二进制。

若公开发布含有引擎的 DMG，仅 README 致谢不够。必须针对实际随包版本准备完整对应源码、修改及构建安装脚本、许可文本和第三方通知，并检查所有依赖的许可证。上游主页链接不是对应源码交付的替代品。见 `THIRD-PARTY-NOTICES.md`。本仓库仅公开 Muxie 源码，不提供内置第三方引擎的自用 DMG。
