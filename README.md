# 歌词译伴 · 整句测试版 0.2

与 Apple Music 并排使用的 iPad 日语歌词翻译工具。需要 iPadOS 27 或更新版本。

## 0.2 的变化

- 使用 ScreenCaptureKit，只请求画面并设置 `capturesAudio = false`，不接入音乐音频、麦克风或音频会话。
- 点击“开始翻译”后直接打开系统画面授权，随后自动准备日语→简体中文翻译。系统授权仍不可省略。
- 默认筛选当前高亮歌词，先合并同一行的识别碎片，最多组合三行；整句稳定后才翻译。也可手动选择歌词区域前 3 行。
- 优先翻译最新完整句；响应过慢时尝试重建会话，并提供重新连接。
- 记住音乐窗口的左右位置和宽度。默认音乐在右侧、约占屏幕宽度 56%。

0.1 已完成一次真机安装，但存在 Music 静音和碎词识别问题。0.2 正在验证；关闭音频捕获不等于已证明 Apple Music 会恢复有声，新捕获权限能否通过免费签名也需要真机确认。

## 打包

在 Actions 中运行 **Build iPad app**。工作流使用 GitHub 的 `xcode-27` 标准预览机器，先运行句子选择测试，再生成工程并构建未签名 IPA。成功后下载 **LyricBridge-v2-visual**。

本项目源码在根目录，`project.yml` 明确列出本版使用的 6 个源文件。`main.swift` 是独立测试入口，不加入 iPad App。其余旧版 ReplayKit 文件暂留以供参考，不会被编译进 0.2。

在 Mac 本地构建需要支持 iPadOS 27 的 Xcode 和 XcodeGen；先执行 `xcodegen generate`，再打开生成的 `LyricBridge.xcodeproj`。现存根目录旧的 plist/pbxproj/安装说明属于 0.1，不用于本版构建。

## 安装及使用

1. 用自己的签名方式安装生成的 IPA；免费个人签名一般需要定期续签。当前屏幕捕获权限是否被保留，以实际签名结果为准。
2. 将 Music 和本 App 并排打开，在“歌词位置与识别方式”中设置正确的左右位置和宽度。
3. 点“开始翻译”，在系统提示中选择包含 Music 的画面；首次按提示准备翻译语言。
4. 验证音乐是否仍有声音，再检查高亮整句及中文译文是否正常；如果出现捕获权限错误，先保留错误信息核查。
5. 换歌时点“换歌 / 清空”，结束时点“停止”。

文字识别和系统翻译在本机完成，不需要翻译 API 密钥。不会保存或上传屏幕录像。

## 测试范围

独立 Swift 测试覆盖碎片合并、暗行排除、相邻换行组合、三行上限、等待稳定和重复抑制。完整 Xcode 编译、签名权限、Music 音频、真实 Vision 结果和系统翻译生命周期，需要分别验证。

## 参考

- [苹果官方画面捕获示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
- [音频捕获开关](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio)
- [GitHub Xcode 27 runner](https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/)
