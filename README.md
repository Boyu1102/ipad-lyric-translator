# 歌词译伴 0.4

跟随 Apple Music 当前播放进度，显示整句原词及中文／英文译文。支持日语→中文、日语→英文、英语→中文；最低 iPadOS 18。

## 使用

1. 用同一 Apple ID 签名覆盖安装，先在 Apple Music 播放歌曲，再点“连接 Apple Music”。
2. 首次允许“媒体与 Apple Music”访问，按提示下载系统翻译语言。Music 可在后台播放，不必分屏。
3. “译文”切换中文／English。原文自动识别日语和英语，也可在“歌词与设置”指定。
4. 同步有偏差时，可按 0.5 秒调整；没有时间轴时可手动切句。
5. 找不到歌词时可手动找歌或导入自己的 LRC/TXT。导入 LRC 可同步，TXT 只能手动切句。

## 本版变化

- 增加英文译文和英文歌曲的中文翻译。切换语言时清除当前译文，并按原文语言、译文语言隔离缓存，避免串语言。
- 英文／罗马音歌名未找到合适原词时，通过 Apple 公开目录的歌曲编号查找同一首歌的日文名称，再查歌词。无编号时先核对英文名称、歌手和时长，避免把同名歌曲当作别名。
- 日文原词优先；少量假名混在大量罗马音中时，不再误判为日文原词。不把罗马音原样重复显示为译文，也不凭空还原汉字。
- 同一记录仅有罗马音同步词、但有日文普通词时，使用日文普通词并明确提示手动切句，不编造时间轴。
- 若公开媒体资料中提供了歌词，可在公共同步歌词缺失时使用该内容。该属性不保证包含 Apple Music 显示的授权歌词。
- 缺词示例 D-D-Dice／Tsukino 的歌曲增加已核实的 TuneCore Japan 官方发行原词后备，并提供来源链接；该来源无时间轴，明确使用手动切句，不假装自动同步。
- 页面聚焦歌曲、当前整句、译文语言和下两句；高级操作收进折叠设置，支持系统深色模式。

## 原理与限制

保留用户在 0.3 真机验证可用的方案：只读取 `MPMusicPlayerController.systemMusicPlayer` 的当前曲目、播放状态和进度，以 LRCLIB 的时间轴跟随整句。不启动屏幕捕获，不使用麦克风，不建立音频会话，不更改 Music 音量、队列或播放状态。旧版捕获源文件不编译进应用。

联网时，只向 LRCLIB 及 Apple 公开目录发送当前曲目名称、歌手、专辑、时长或歌曲编号，官方发行后备会访问已核实的 TuneCore Japan 公开页面。不传输屏幕、音乐音频、账号或音乐库清单。歌词请求顺序执行、缓存结果，并遵守 Retry-After。系统翻译在设备上完成。

公共歌词库与 Apple Music 的授权歌词覆盖不同，Apple Music 有词不代表本 App 一定能获取。没有可靠原词或时间轴时会提示，不伪造同步。系统翻译对诗性表达和口语仍可能不准确。App 回到前台后重新读取播放时间，不承诺锁屏或被系统挂起后继续运行。

实查示例：“I am...”／Atarayo 对应「僕は...」，“Polar night”对应“極夜”，日文名称可找到日文同步歌词。“To the Beyond, from a Nameless Shore”对应“彼方へ、名もなき海辺より”，此次在 LRCLIB 中仍未查到同步歌词，已接入其官方发行页面的普通歌词后备。这是当前查询结果，并非永久覆盖保证。

## 验证与打包

Actions → **Build iPad app**，成功后下载 **LyricBridge-v4-languages**，内含未签名 IPA。版本 0.4.0，构建号 4，保持原应用编号，可使用自己的个人签名覆盖安装。

自动检查覆盖时间轴前进／后退／间奏、整句合并、日文原词与混合罗马音、英文来源、语言缓存隔离、歌曲版本及目录别名匹配，并用模拟 HTTP 响应检查有／无歌曲编号的完整查找路径，以及官方普通歌词的内容提取、网页结构变化和不同剪辑防误配。构建还检查未链接 ScreenCaptureKit / ReplayKit，未声明屏幕捕获权限。新语言的系统下载、翻译质量及实际歌曲覆盖仍需真机体验确认。

## 官方资料

- [Apple systemMusicPlayer](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer)
- [Apple 媒体项目歌词属性](https://developer.apple.com/documentation/mediaplayer/mpmediaitem/lyrics)
- [Apple 公开目录搜索与编号查询](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/)
- [LRCLIB API](https://lrclib.net/docs)

- [D-D-Dice / Tsukino 官方发行原词](https://linkco.re/taSCnaZS/songs/3545789/lyrics?lang=en)
