VNC and RDP now support Fit Window, Retina High Resolution and Fixed Resolution. Configure the mode per bookmark or change it from an open tab's context menu, including detached windows. Existing bookmarks continue to fit the window. Fixed presets are 720p, 1080p, 1440p and 4K.

Retina mode follows the screen backing scale and requests RDP desktop UI scaling. Remote servers and applications determine whether scaling takes effect; VNC UI scaling must be configured remotely. Requests remain within 4096×2160. The tab menu displays the actual dimensions of received frames, rather than assuming a requested resize succeeded.

Protocol validation uses local synthetic VNC/RDP servers, including RDP 200% scaling and a same-size update back to 100%. ARM and Intel packages are ad-hoc signed, not notarized; physical Intel testing remains pending. Personal configuration and credentials are excluded from release assets.

Validation: 84 tests, zero failures, one optional environment-dependent skip. Tests cover mode calculations, Retina limits, fixed-size invariance, and older bookmark compatibility.

Installed and restarted on Apple Silicon. Actual tab-menu clicks verified Debian xrdp at 2934×1746 in Retina mode, 1920×1080 and 1280×720 in fixed mode, and 1466×873 after returning to Fit Window. A real VNC server returned 2934×1746, 1920×1080 and 1466×873 for those modes. Mode preferences were restored to Fit Window. Reconnecting now replaces the old canvas so the new connection can draw and resize correctly.

The Windows RDP server initially returned the fit-window frame but later disconnected and timed out during activation; its full mode-switch validation remains incomplete. The VNC server returned black framebuffer content during this check; resolution changes were verified from the received frames, without claiming visible desktop content.

---

VNC、RDP 新增适应窗口、Retina 高清和固定分辨率三种模式，可在书签编辑界面或已打开标签的右键菜单切换，独立窗口也支持。按书签保存，旧书签继续默认适应窗口。固定预设提供 720p、1080p、1440p 与 4K。

Retina 模式跟随屏幕像素倍率，并向 RDP 请求界面缩放；实际效果取决于远端服务和应用，VNC 的界面缩放需在远端系统设置。请求仍限制在 4096×2160 内。标签右键显示实际收到的画面分辨率，不把请求值当成调整成功。

本机模拟服务已验证 VNC/RDP 协议，包括 RDP 200% 缩放及同尺寸切回 100%。ARM / Intel 安装包为临时签名，尚未公证；Intel 真机验证待完成。发行包不包含个人配置及凭据。

验证：84 项测试无失败，1 项按环境条件跳过。覆盖三种模式计算、Retina 上限、固定尺寸不随窗口改变及旧书签兼容。

已在 Apple Silicon 安装并重启，通过实际点击标签菜单验证 Debian xrdp：Retina 返回 2934×1746，固定模式返回 1920×1080、1280×720，切回适应窗口返回 1466×873。真实 VNC 服务对应返回 2934×1746、1920×1080、1466×873。测试书签已恢复适应窗口。另修复重连时旧画布被复用的问题，使新连接可正常绘制与调整尺寸。

Windows RDP 服务首次收到适应窗口画面，但随后断线并出现连接激活超时，完整模式切换验证尚未完成。此次 VNC 服务返回黑色画面内容，分辨率切换由实际收到的帧确认，未据此声称桌面内容正常显示。
