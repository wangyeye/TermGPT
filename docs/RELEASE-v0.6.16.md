Drag tabs out of the tab strip to move the existing session into a separate window; dragging within the strip still reorders tabs. A context menu entry also opens a separate window. Terminal, web, VNC and RDP sessions retain their own controls, with no AI or library panels. Closing a detached window ends only its session. On restart, detached sessions restore as pending main-window tabs.

ARM/Intel packages are ad-hoc signed, not notarized; physical Intel testing is pending. Personal configuration and credentials are excluded.

---

支持拖出标签栏，把原有会话移到独立窗口；标签栏内仍可拖动排序，也可右键选择“移到独立窗口”。终端、网页、VNC、RDP 保留自身功能，不包含 AI 助手或命令库面板。关闭独立窗口仅结束自身会话；重启后作为主窗口待连接标签恢复。

ARM/Intel 临时签名、尚未公证，未进行 Intel 真机验证。发布包不包含个人配置或密码。

Validation: 74 tests, zero failures, one optional skip. Actual GUI checks covered context-menu detachment, terminal input, search, Command-F, closing and preservation of main-window tabs. Pointer dragging could not be automated because the UI tool returned “noWindowsAvailable”; live drag-out/reordering and remote-session migration remain unverified.

验证：74 项测试无失败，一项可选测试跳过。实际界面检查覆盖右键拆窗、终端输入、搜索、⌘F、关闭及主窗口标签保留。界面工具坐标拖拽返回“noWindowsAvailable”，真实拖出/排序及远程会话迁移尚未实测。
