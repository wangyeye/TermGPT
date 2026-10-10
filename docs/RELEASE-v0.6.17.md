Tab dragging now uses a native AppKit drag session so dragging can continue beyond the originating window. Transient zero-sized layouts during migration no longer resize the terminal buffer.

Return detached tabs to the main window by dragging the session header onto its tab bar, or use **Move back to main window**. Returning retains the existing session instead of reconnecting it.

Workspace restoration now preserves main and detached window positions and sizes, tab distribution and selection, the focused window, and open Notepad / Command Library windows. Windows are fitted to available displays after a monitor is removed. Restored sessions remain disconnected until **Restore Connection** is clicked. Older workspace JSON remains compatible. Quick Open follows the application theme and also lists detached sessions.

ARM and Intel packages are ad-hoc signed, not notarized. Physical Intel testing is pending. Personal configuration and credentials are excluded.

---

独立窗口会话标题可拖回主窗口标签栏，也可点击**移回主窗口**；移回保留原会话，不重新连接。

工作区恢复现保存主窗口与独立窗口的位置、大小、标签分布、选中标签、当前窗口，以及已打开的记事本和常用命令库窗口。移除显示器后，窗口会回到可见范围。恢复的连接仍需点击**恢复连接**才启动；兼容旧版 JSON 配置。

ARM / Intel 安装包为临时签名，尚未公证；Intel 真机验证待完成。发布包不包含个人配置或密码。

Validation: 78 tests, zero failures, one optional skip. Live GUI validation is described below after installation.

Actual GUI validation: returning a live local terminal preserved its command/output search results. Restart restored five main tabs, one detached window and two library windows with an identical layout fingerprint, including frames and focus; sessions remained pending. Quick Open was visually verified in dark mode. Native pointer dragging still awaits manual verification; automated coordinate actions did not produce a usable drag.

实际界面验证：本地终端移回后保留命令与输出，搜索结果一致。重启恢复了 5 个主窗口标签、1 个独立窗口和 2 个库窗口，含位置、大小和焦点的布局摘要完全一致，连接保持待恢复状态。快速打开暗色主题已截图验证。原生鼠标拖拽仍待人工验证，自动化坐标操作未产生有效拖拽。
