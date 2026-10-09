TermGPT v0.6.10 adds connection diagnostics, audio status and reconnect.

- SSH/RDP/VNC tab menus provide Reconnect and optional Automatically Reconnect (off by default, at most three attempts after an unexpected disconnect). Authentication/certificate errors are not automatically retried.
- Diagnose checks the TCP port without login and explains known network, DNS, authentication, certificate/protocol and permission errors. Desktop failure panels offer Diagnose/Reconnect. Logs stay local.
- Desktop menus show audio state and per-connection Mute/Unmute, including VNC bell notifications. No top desktop status bar is added.

RDP needs server audio redirection; xrdp needs its audio modules. Continuous VNC audio requires QEMU Audio support. TCP reachability is not a login test. macOS 13+; ARM and Intel packages are ad-hoc signed, not notarized. Physical Intel testing is pending. Personal configuration, credentials and logs are excluded.

---

新增连接诊断、声音状态与重连：

- SSH/RDP/VNC 标签右键提供重连和可选自动重连，自动重连默认关闭，意外断线最多重试三次；认证及证书错误不自动重试。
- 诊断只检查 TCP 端口，不尝试登录；根据协议证据解释网络、DNS、认证、证书/协议及权限问题。桌面失败面板提供诊断和重连，日志仅本机保存。
- 桌面右键显示声音状态，可按连接静音，包括 VNC 提示音；不新增顶部状态栏。

RDP 需要服务端音频重定向，xrdp 需要音频模块；连续 VNC 声音需要 QEMU Audio。端口可达不代表登录成功。macOS 13+，支持 ARM/Intel，临时签名、尚未公证；未进行 Intel 真机验证。不包含个人配置、密码或日志。
