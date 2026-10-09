TermGPT v0.6.9 adds remote audio and browser tab management.

- RDP remote sound plays through the Mac’s current output using the native macOS audio backend. The server must enable audio redirection; xrdp requires its audio modules.
- VNC supports standard bell notifications and continuous PCM sound from servers supporting the QEMU Audio extension. Ordinary VNC services without this extension cannot stream audio. Microphone forwarding is not included.
- Right-click a WEB tab → **Close Other Tabs** to keep and select that tab, closing all other central tabs.

Validation: synthetic RDP PCM negotiation/playback acknowledgment and VNC AudioQueue consumption, plus desktop/input/clipboard/resize checks. Actual UI clicks verified Close Other Tabs. Both architecture packages are signature- and privacy-checked. Physical speaker listening and Intel hardware testing are not claimed.

Requires macOS 13+. Download arm64 for Apple Silicon or x86_64 for Intel. Packages are ad-hoc signed, not notarized. Personal configuration, credentials, bookmarks, chats and logs are excluded.

---

此版本新增远端声音和网页标签管理。

- RDP 声音通过 Mac 当前输出设备播放，需服务端开启音频重定向；xrdp 需对应音频模块。
- VNC 支持标准提示音，以及提供 QEMU Audio 扩展的服务端连续声音。没有此扩展的普通 VNC 服务无法传送音频。不包含麦克风转发。
- WEB 标签右键新增**关闭其他标签**，保留并切换到选中的标签，关闭其余中间标签。

已验证合成 RDP 音频协商与播放确认、VNC 播放队列消费，以及画面、输入、剪贴板和分辨率回归；已实际点击验证关闭其他标签。两个架构均检查签名和隐私，未宣称扬声器听音或 Intel 真机验证。

需要 macOS 13+。Apple Silicon 选择 arm64，Intel 选择 x86_64。临时签名，尚未公证。发行包不包含个人配置、密码、书签、聊天或日志。
