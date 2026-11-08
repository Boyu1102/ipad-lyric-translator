# 用借来的 Mac 安装测试版

当前交付是测试工程，已检查文件结构和工程引用，尚未在 Xcode 编译，也没有在 iPad 上验证持续识别和翻译。

## 先确认电脑环境

1. 点 Mac 左上角苹果图标 → 关于本机。记录芯片或处理器型号、macOS 版本。
2. 如果已有 Xcode，打开它，点菜单 Xcode → About Xcode，记录版本。
3. 把这几项告诉助手，确认与 iPadOS 27.0.1 的连接支持和可用开发工具。不要先升级同学电脑的系统。

没有 Xcode 时，可从 Mac App Store 下载免费 Xcode。具体能安装哪个版本取决于 Mac 的系统和硬件，先确认再下载。第一次打开可能要求安装平台组件，按需要安装 iOS 平台支持。

## 打开工程

1. 将“歌词译伴_Mac直接打开版.zip”转移到 Mac，双击解压。
2. 双击里面的 `LyricBridge.xcodeproj`。不需要访问 GitHub，也不需要运行终端命令。
3. 用能传输数据的 USB-C 数据线连接 iPad，在 iPad 上选择“信任这台电脑”。

## 给自己的设备签名

1. 在 Xcode → Settings → Accounts（部分版本称 Apple Accounts）添加自己的 Apple 账号。用 Xcode 的账号设置即可，不必退出同学 Mac 的 iCloud 或 App Store。
2. 点左边蓝色工程图标，在 TARGETS 中选择 `LyricBridge` → Signing & Capabilities，勾选 Automatically manage signing，在 Team 中选择自己的 Personal Team。
3. 将 Bundle Identifier 改为唯一名称，例如 `com.自己的英文代号.lyricbridge`。这里的代号仅用英文字母和数字，去掉中文占位内容。
4. 对 `Broadcast` 目标做相同签名设置；其 Bundle Identifier 必须是主 App 的完整名称再加 `.broadcast`，例如 `com.自己的英文代号.lyricbridge.broadcast`。两个目标都要选同一个 Personal Team。
5. 在顶部运行设备中选择自己的 iPad，Scheme 选择 `LyricBridge`，点击 ▶ 或按 Command+R。
6. 按 iPad 提示开启开发者模式、重启确认或信任开发者。不同版本提示可能不同；如果没有对应入口，先让 Xcode 连接并尝试运行一次。
7. 若出现编译、签名、连接错误，把完整报错交给助手。不要因一次失败就购买开发者会员。

苹果允许免费账号在个人设备上测试，但 Personal Team 有能力限制，签名通常每 7 天需要更新。能否签名这个含广播扩展的工程，仍以实际结果为准。借用一次 Mac 并不等于 App 永久有效；免费测试期间，应计划能再次借用电脑重新运行签名。后续若验证确实好用，再讨论适合长期使用的安装方式。

## 安装后的使用

1. 将 Apple Music 与歌词译伴并排打开，音乐放左侧。
2. 在歌词译伴点“启用翻译”，完成系统要求的日语、中文语言下载。
3. 设置音乐占整个屏幕的宽度，避免识别区域覆盖译文 App。
4. 点“准备识别”，再点圆形录屏按钮，选择“歌词译伴识别”并开始直播。
5. 观察原文是否持续出现、译文是否自动补上、音乐是否正常播放。先测 1 分钟，再测 5 分钟。
6. 点“停止”或使用控制中心结束录屏。换歌时点“换歌 / 清空”。

本工程采用本机识别和系统翻译，不需要腾讯云服务器、翻译 API 账号或收集音乐音频。当前按文字行翻译，尚无精确演唱行同步。

## 用完借来的电脑

确认文件保存位置与后续更新办法后，可从 Xcode 账号设置中移除自己的账号。不要删除同学原有的账号、证书或项目。移除账号不会延长已经安装的测试签名有效期。

官方参考：

- Xcode 系统要求：<https://developer.apple.com/xcode/system-requirements>
- 免费个人测试和账号限制：<https://developer.apple.com/help/account/basics/about-your-developer-account>
- Xcode 运行到设备：<https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html>
