VNC and RDP now support Fit Window, Retina High Resolution and Fixed Resolution. Configure the mode per bookmark or change it from an open tab's context menu, including detached windows. Existing bookmarks continue to fit the window. Fixed presets are 720p, 1080p, 1440p and 4K.

Retina mode follows the screen backing scale and requests RDP desktop UI scaling. Remote servers and applications determine whether scaling takes effect; VNC UI scaling must be configured remotely. Requests remain within 4096×2160. The tab menu displays the actual dimensions of received frames, rather than assuming a requested resize succeeded.

Protocol validation uses local synthetic VNC/RDP servers, including RDP 200% scaling and a same-size update back to 100%. ARM and Intel packages are ad-hoc signed, not notarized; physical Intel testing remains pending. Personal configuration and credentials are excluded from release assets.

---

VNC、RDP 新增适应窗口、Retina 高清和固定分辨率三种模式，可在书签编辑界面或已打开标签的右键菜单切换，独立窗口也支持。按书签保存，旧书签继续默认适应窗口。固定预设提供 720p、1080p、1440p 与 4K。

Retina 模式跟随屏幕像素倍率，并向 RDP 请求界面缩放；实际效果取决于远端服务和应用，VNC 的界面缩放需在远端系统设置。请求仍限制在 4096×2160 内。标签右键显示实际收到的画面分辨率，不把请求值当成调整成功。

本机模拟服务已验证 VNC/RDP 协议，包括 RDP 200% 缩放及同尺寸切回 100%。ARM / Intel 安装包为临时签名，尚未公证；Intel 真机验证待完成。发行包不包含个人配置及凭据。
