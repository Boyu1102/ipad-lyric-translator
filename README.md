# 歌词译伴 · 不读屏版 0.3

为 Apple Music 提供日语歌词中文翻译。最低 iPadOS 18，使用系统 Translation 框架。

## 这次改变了什么

0.1 和 0.2 的读屏路径在实际设备上影响了 Music 的声音，并出现误识别自身界面、错选歌词和追踪停滞。0.3 不再编译或启动任何屏幕捕获功能，不使用麦克风、不修改 Music 音量或播放队列，不需要分屏或左右区域设置。

本版通过 `MPMusicPlayerController.systemMusicPlayer` 读取 Music 当前曲目、播放状态和进度，用 LRCLIB 的 LRC 时间轴选择整句歌词，交由设备上的 Translation 框架翻译。歌词来源不是 Apple Music 的屏幕或非公开歌词接口。

## 使用

1. 先结束旧版仍在运行的屏幕共享/录屏，确认 Apple Music 恢复正常声音。
2. 安装 0.3，先在 Music 播放歌曲，再点本 App 的“连接 Apple Music”。首次按提示允许“媒体与 Apple Music”访问。
3. 本 App 自动匹配歌名、歌手、专辑和时长，并跟随播放时间。Music 可以在后台；本 App 可以全屏。
4. 歌词有时间偏差时，展开“歌词来源与同步”，调整提前或延后 0.5 秒。
5. 没有可靠匹配时选择正确版本，或手动找歌、导入自己的 LRC/TXT。无时间轴歌词或 Music 没提供播放时间时会明确提示手动切句，不伪造自动同步。

联网查找仅把歌名、歌手、专辑和时长发给 LRCLIB，不传输屏幕、音乐音频、Apple 账号或音乐库清单。服务请求顺序执行、缓存匹配，并遵守 Retry-After。翻译在设备上进行。

## 验证和限制

- 自动测试覆盖 LRC 多时间标签、小数与 offset、同时间多行、间奏空行、前奏、向前/向后拖动、整句文本和歌曲版本匹配。
- 构建检查安装包版本、Music 权限声明，并检查未链接 ScreenCaptureKit / ReplayKit。
- 当前设备的 Music 是否返回曲目和进度，以及真实系统翻译的表现，仍需真机验证；编译和单元测试不能证明这些已经可用。
- 歌词服务不保证覆盖全部歌曲或版本，时间轴可能与 Music 有偏差。没有时间轴时只支持手动切句。
- 歌词解释及诗性表达仍受系统翻译质量限制；本版主要消除 OCR 造成的残缺、混行和自我识别。
- App 前台可见时跟随；锁屏或 App 被系统挂起时不承诺继续运行，回到前台后重新读取 Music 当前时间。

## 打包

Actions → **Build iPad app**。成功后下载 **LyricBridge-v3-music**。该文件包含未签名 IPA，可使用自己的个人开发签名安装。生成 App 的版本为 0.3.0、构建号 3。

源文件由 `project.yml` 明确指定。根目录保留的旧版 OCR/捕获源文件和旧说明不编译进 0.3；其历史可用于回溯，但不代表本版功能。

## 官方依据和服务文档

- [苹果 systemMusicPlayer](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer)
- [苹果 nowPlayingItem](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/nowplayingitem)
- [苹果播放时间接口](https://developer.apple.com/documentation/mediaplayer/mpmediaplayback)
- [苹果 Media Player 权限说明](https://developer.apple.com/documentation/mediaplayer)
- [LRCLIB API](https://lrclib.net/docs)
