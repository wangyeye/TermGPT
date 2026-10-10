Tab dragging now uses a native AppKit drag session so dragging can continue beyond the originating window. Transient zero-sized layouts during migration no longer resize the terminal buffer.

Return detached tabs to the main window by dragging the session header onto its tab bar, or use **Move back to main window**. Returning retains the existing session instead of reconnecting it.

Workspace restoration now preserves main and detached window positions and sizes, tab distribution and selection, the focused window, and open Notepad / Command Library windows. Windows are fitted to available displays after a monitor is removed. Restored sessions remain disconnected until **Restore Connection** is clicked. Older workspace JSON remains compatible.

ARM and Intel packages are ad-hoc signed, not notarized. Physical Intel testing is pending. Personal configuration and credentials are excluded.

---

独立窗口会话标题可拖回主窗口标签栏，也可点击**移回主窗口**；移回保留原会话，不重新连接。

工作区恢复现保存主窗口与独立窗口的位置、大小、标签分布、选中标签、当前窗口，以及已打开的记事本和常用命令库窗口。移除显示器后，窗口会回到可见范围。恢复的连接仍需点击**恢复连接**才启动；兼容旧版 JSON 配置。

ARM / Intel 安装包为临时签名，尚未公证；Intel 真机验证待完成。发布包不包含个人配置或密码。

Validation: 78 tests, zero failures, one optional skip. Live GUI validation is described below after installation.
