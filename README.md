# 歌词译伴 · iPad 测试工程

状态：源代码已准备；尚未经过 Xcode 编译、签名安装或 iPad 真机验证。
适用目标：iPadOS 18 以上，重点测试用户的 2024 iPad Pro / iPadOS 27.0.1。

**已有或可以借用 Mac：直接看 [Mac 安装步骤](Mac安装步骤.md)，无需 GitHub、Homebrew、XcodeGen 或腾讯云。工程内已附可直接打开的 `LyricBridge.xcodeproj`。**

这是与 Apple Music 并排运行的独立 App。用户主动开启系统屏幕直播，广播扩展在设备上识别日文，再交由主 App 的苹果 Translation 框架翻译为简体中文。没有翻译 API 密钥或付费接口。

## 先做什么

1. 注册免费的 GitHub 账号：<https://github.com/signup>。无需购买套餐或绑定支付方式。
2. 创建名为 `ipad-lyric-translator` 的仓库。本工程不含个人信息、歌词或密钥；若选择 Public，源码会公开，标准 macOS 打包机器对公开仓库免费。Private 仓库使用账户的包含额度，超额前先查看账单设置，不启用付费预算。
3. 解压工程，将里面的文件上传到仓库根目录；不要额外套一层 `LyricBridge` 文件夹。根目录应能看到 `project.yml`、`README.md`、`App`、`Broadcast`、`Shared` 和 `.github`。
4. 注意 `.github/workflows/build.yml` 必须上传。部分文件选择界面会隐藏点开头的目录；若遗漏，可在 GitHub 用 Add file → Create new file 创建该路径并复制 `build.yml` 的全部内容。
5. 打开仓库 Actions 页面，查看 `Build iPad app`。若没有自动开始，打开这个工作流，点 Run workflow。等待绿色对勾；红色失败时把失败步骤的日志交给助手修复，不要付费重试。
6. 在成功运行页底部 Artifacts 下载 `LyricBridge-unsigned`，解压得到 `LyricBridge-unsigned.ipa`。

## Windows 安装阶段

本工程通过 GitHub 的 Mac 打包；你的电脑无需安装 Xcode。生成的 IPA 是未签名文件，不能在 iPad 上直接点开安装。

可在 Windows 使用官方 Sideloadly：<https://sideloadly.io/>。
安装其官网要求的苹果设备支持组件，USB 连接 iPad 并在 iPad 上信任电脑。把 IPA 拖入 Sideloadly，用自己的 Apple 账号完成签名安装。不要把密码、验证码或签名材料发到聊天或仓库。需要打开开发者模式、信任开发者时，按 iPad 当前系统提示操作。

免费账号签名通常有效 7 天，需要续签；Sideloadly 支持在电脑检测到设备时自动续签。此工程尚未实测该工具、免费签名与 iPadOS 27.0.1 的组合。遇到扩展签名或安装失败，应先保留错误日志核查，不能据此承诺一定免费安装成功。

不需要购买 Apple Developer 会员来进行上述免费签名尝试；若改用 TestFlight，才进入另一套付费开发者分发流程。

## 在 iPad 上第一次使用

1. 把 Apple Music 放在屏幕左侧，歌词译伴放在右侧；建议音乐约占 60%。两个 App 都要保持可见。
2. 在歌词译伴中点“启用翻译”，按系统提示准备日语和简体中文语言资源。第一次下载建议使用 Wi-Fi。
3. 展开“调整识别区域”，设置音乐在左侧还是右侧，以及它占整个屏幕的宽度。识别区域不能覆盖译文窗口，否则会重复识别自己的日文。
4. 点“准备识别”，再点圆形录屏按钮，在系统弹窗中选择“歌词译伴识别”并开始直播。这里的“直播”是苹果的系统名称；本工程没有上传屏幕的视频服务器。
5. 播放歌曲。文字稳定出现在连续两次识别中后，会加入列表并翻译。系统翻译首次准备失败时，可以点“启用翻译”重试。
6. 换歌时点“换歌 / 清空”。结束时点“停止”或从控制中心停止录屏。App 的停止请求可能使系统显示“已停止歌词识别”，属于主动结束。

如果全无文字：先检查两个窗口仍可见、直播仍开启、音乐位置和宽度设置正确。若收到“识别连接未能建立”，停止直播并重新打开 App。端口被其他本机进程占用时主 App 会显示错误。

## 当前功能与限制

- 约每 0.8 秒做一次本机 OCR，只处理设定区域；忽略麦克风和音乐音频，不保存录屏或截图。
- 原文和译文只保存在主 App 的内存中，最多保留 80 行，不包含云端服务或歌词网站抓取。
- 苹果翻译可能需要先下载语言资源；以设备提示和真机测试为准。
- 当前按识别文字行翻译，尚未实现跨行成句、当前演唱行精确追踪、时间轴同步或罗马音。能预先读到附近歌词，所以显示的是近期识别到的歌词，不保证每次只有当前唱到的那一句。
- 短暂滚动模糊、断行、歌词重复和窗口位置变化可能导致漏识别或重复翻译。英文整行和单字行当前会跳过。
- 主 App 需要与音乐并排可见；不承诺隐藏 App、锁屏或任意其他 App 上方悬浮时继续显示译文。
- 普通录屏测试已由用户确认通过，但这不等于广播扩展或翻译已经通过真机测试。

## 实现说明

为兼容现有打包环境并减少免费签名的能力要求，这个测试工程采用公开的 ReplayKit Broadcast Upload Extension 路线，不要求 iPadOS 27 新屏幕捕获权限或 App Groups。ReplayKit 的相关 API 在新系统中逐渐由 ScreenCaptureKit 取代；这里保留兼容实现，是否可用以 iPadOS 27.0.1 真机结果为准。

扩展用 Vision 识别日文。主 App 的 `NWListener` 仅绑定 `127.0.0.1:54137`，扩展通过同机回环 TCP 交换文本和裁剪设置，避免依赖 App Groups；不监听局域网，也不上传屏幕。该通信仍需要实际验证是否受 iPadOS 进程或网络策略影响。回环协议无身份认证，只适合本机个人原型；正式分发前应改为受支持的、经过身份校验的跨进程通信，不应直接公开分发为成熟产品。

翻译使用 `.translationTask` / `TranslationSession`，在窗口可见期间执行；不会通过空音频伪造后台运行。构建指定 iOS 18 最低版本，所以不必依赖 iOS 27 SDK。

## 验证清单

- [ ] GitHub 打包成功，App 与广播扩展均包含在 IPA 中。
- [ ] Windows 签名安装成功，系统列表能选择“歌词译伴识别”。
- [ ] 并排显示时，主 App 持续收到扩展识别文字。
- [ ] 左/右区域设置、竖/横屏方向符合真实画面，不识别本 App。
- [ ] Music 播放不中断，连续识别 5 分钟无扩展内存退出。
- [ ] 初次语言下载及连续中文翻译正常；拒绝下载时显示可理解的错误。
- [ ] 停止、取消、切歌、翻译失败重试及重新开始可用。
- [ ] 断网后已下载语言的实际行为符合预期。

## 官方资料与工具说明

- ReplayKit：<https://developer.apple.com/documentation/replaykit>
- Vision OCR：<https://developer.apple.com/documentation/vision/vnrecognizetextrequest>
- Translation：<https://developer.apple.com/documentation/translation>
- GitHub 托管打包机器与免费条件：<https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job>
- Sideloadly 免费账号与续签说明：<https://sideloadly.io/faq.html>
