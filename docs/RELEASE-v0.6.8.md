TermGPT v0.6.8 adds browser-tab Force Reload and improves embedded web login and xrdp compatibility.

- Right-click a WEB tab → **Force Reload** to reload from the server, including when the address bar is hidden.
- Website login forms offer **Save and Autofill**; saved credentials fill the matching website origin without submitting the form. Dynamic forms, legacy modem login buttons and JavaScript password prompts, including noVNC, are supported.
- VNC/RDP desktop content uses the full pane; connection actions are available in the tab context menu.
- Fix xrdp disconnections during automatic resolution changes by handling reactivation updates and resizing bitmap decoder capacity.
- Add local-network usage text and a documented RDP diagnostic script.

**Downloads:** choose `TermGPT-macOS-arm64.zip` for Apple Silicon, or `TermGPT-macOS-x86_64.zip` for Intel. Requires macOS 13+.

Packages use ad-hoc signing and are not notarized. Both architecture packages pass signature and privacy checks; live testing was performed on Apple Silicon, including xrdp and Windows RDP resizing. Physical Intel testing has not been performed. Personal configuration, passwords, bookmarks, chats and logs are excluded.

---

此版本新增浏览器标签右键“强制刷新”，改善网页登录与 xrdp 兼容性。

- WEB 标签右键选择**强制刷新**，地址栏隐藏时也可使用。
- 网站登录表单可选择**保存并自动填充**；只对匹配的网站自动填入，不自动提交。支持动态表单、旧式光猫登录按钮及 JavaScript 密码弹窗（包括 noVNC）。
- 移除 VNC/RDP 顶部状态栏，相关操作放入标签右键菜单。
- 修复自动调整分辨率时 xrdp 断开的问题，同时同步画面解码器尺寸。
- 增加本地网络用途说明和 RDP 诊断脚本使用文档。

Apple Silicon 下载 `TermGPT-macOS-arm64.zip`；Intel 下载 `TermGPT-macOS-x86_64.zip`。需要 macOS 13 或更高版本。

安装包采用临时签名，尚未公证。两个架构均通过签名和隐私检查；Apple Silicon 已实测 xrdp 和 Windows RDP 分辨率切换，尚未进行 Intel 真机测试。发行包不包含个人配置、密码、书签、聊天或日志。
