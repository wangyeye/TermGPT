# TermGPT

[English](README.md) | **简体中文**

原生 macOS 终端与 AI 聊天工作台。使用 SwiftUI、AppKit 和 SwiftTerm；终端独立运行，AI 可按需读取用户选择的终端上下文。

## 下载

从 [GitHub Releases](https://github.com/wangyeye/TermGPT/releases) 下载 macOS 13+ 安装包：

- Apple Silicon（M1/M2/M3 等）：`TermGPT-macOS-arm64.zip`
- Intel Mac：`TermGPT-macOS-x86_64.zip`

解压后将 `TermGPT.app` 拖入 Applications。提供 SHA256SUMS 校验文件。应用暂未 Developer ID 签名或公证；签名验证不等于 Gatekeeper 已批准。

![TermGPT icon](Assets/AppIcon.png)

## 功能

- 真实 PTY 本地终端，支持 ANSI、回滚、交互式 SSH 和 vim/top。
- 多终端标签、SSH 书签编辑、重命名、删除、文件夹分组、密码或私钥登录，使用系统 OpenSSH。
- 独立多聊天，支持重命名、删除、流式回复、取消、历史保存与导出。生成过程中不会自动滚动，可拖动滚动条并复制已生成命令；聊天顶部“滚动到最新”按钮用于手动跳转。
- 只有明确标记为 Shell 的代码块提供填入和执行；报错、日志、未标记引用及其他语言代码只提供复制。AI 回答使用 bash 标记命令、text 标记引用。
- 聊天分别显示上下文来源与命令目标（含主机、用户信息）。生成期间分析来源保持为本次发送的来源，填入/执行跟随当前终端；锁定上下文与执行目标不同时，命令卡显示提醒。
- 右键终端标签页可关闭当前、全部或右侧标签页；左右拖拽可排序，不会重启会话。关闭标签页会终止对应终端/SSH 会话。本地 Shell 与文件夹对齐，文件夹内书签缩进显示。
- ChatGPT 错误提示区分额度用尽、请求过于频繁、回复长度和内容限制；服务返回恢复时间时会显示。
- ChatGPT 为首选；OpenAI API、Ollama、LM Studio 和兼容接口位于 Advanced / Other Providers。
- 右上角布局工具栏可显示 / 隐藏书签和聊天栏、切换仅终端，布局自动保存。
- 中英双语界面，语言可选跟随系统 / English / 中文；系统语言为中文时使用中文，其他语言默认英语。
- 整体主题支持跟随系统、浅色与深色，覆盖界面、弹窗、输入框和终端。
- 上下文模式：Auto、Off、选中文本、最近 50/200 行、整个会话；支持固定上下文。
- 终端右键 Ask AI / Explain / Fix / Generate command。
- 代码块支持复制、填入和执行。低风险单行命令直接执行，未知或高风险命令需要点击“确认执行”，不需输入 RUN。
- 发送前自动脱敏可在设置中开启或关闭，发送时按设置后台处理，无确认弹窗。
- ChatGPT 登录数据、API Key 和 SSH 密码存储到本机 JSON 配置，不使用钥匙串。

## 环境检查与构建

需要 macOS 13+、Swift 5.9+、Xcode Command Line Tools、系统 SSH 和 zsh。测试需要完整 Xcode 的 XCTest；当前测试脚本定位标准 `/Applications/Xcode.app`。构建不需要 Rust、Node 或 npm，SwiftTerm 已随源码提供。

```bash
cd TermGPT
./scripts/check-environment.sh
./scripts/build.sh
./scripts/run.sh
```

输出为 `dist/TermGPT.app` 和 `dist/TermGPT-macOS-arm64.zip`。发行包分别提供 arm64 和 x86_64；Intel 包完成交叉编译和架构检查，尚未在实体 Intel Mac 实测。App 使用本地 ad-hoc 签名，没有 Developer ID 签名或公证。环境脚本会在缺少依赖时退出，不更改系统默认工具链或接受 Xcode 许可。

若工作目录由文件同步服务管理，建议解压 ZIP 到本机目录后使用；脚本在临时目录签名，避免文件同步元数据影响签名。

## 使用

1. 启动后直接使用本地 Shell。点击 SSH 书签旁的 `+` 添加主机；每项的 `…` / 右键菜单可编辑、删除和移动到文件夹，文件夹按钮用于新建、改名和删除分组。登录方式可选 SSH config / Agent、保存密码或私钥文件。密码保存在本机 JSON 配置，首次连接仍需确认主机指纹；不提供跳板机功能，旧跳板机字段忽略。
2. 打开设置，点击 Continue with ChatGPT，在系统浏览器完成登录和套餐授权。服务决定套餐、额度和模型权限；未返回套餐名时不会推测为 Plus。
3. 其他供应商在 Advanced / Other Providers 配置。OpenAI API 需要独立密钥；Ollama 默认 `http://127.0.0.1:11434/v1`，LM Studio 默认 `http://127.0.0.1:1234/v1`，本地服务需先启动并填写实际模型名。
4. 在聊天输入框按 Enter 发送、Option+Enter 换行。中文输入法确认候选时不会发送。
5. 聊天列表每项的 `…` 菜单或右键菜单可重命名与删除。自定义名称保留，删除当前聊天后切换到相邻聊天，删除最后一项会创建空白聊天；正在回复时操作暂不可用。
6. 用 Context 选择本次需要附带的内容。Auto 是启发式判断；明确控制发送范围时使用 Off 或手动模式。
7. 在 Terminal & Privacy 选择跟随系统 / 浅色 / 深色主题，保存后应用并持久化。也可在此设置“发送前自动脱敏”，保存后生效。默认开启；关闭后消息、历史和所选终端上下文会原样发送给当前供应商。
8. 右上角工具栏的左右侧栏按钮分别控制书签栏与聊天栏；布局菜单可恢复默认，矩形按钮切换仅终端。隐藏聊天不会删除记录或中止回复。用 Cmd+, 可随时打开设置，在“界面语言”选择跟随系统 / English / 中文并保存，立即切换；聊天、书签名称和终端输出不翻译。
9. AI 不会自行执行命令。“填入”不发送 Enter；“执行”针对当前可见终端，发送前清除正常 Shell 输入行。不要在密码提示、vim 或其他交互程序中点击执行。

ChatGPT 的 Auto 选择服务器模型目录首个可见模型，不等同于 ChatGPT 网页自动路由。连接与推理使用官方 OAuth 和 Responses 接口；服务可用性及授权由官方服务控制。实现参考：[登录](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)、[模型和推理](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)、[会话管理](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| Cmd+T | 新建终端 |
| Cmd+W | 关闭终端并结束进程 |
| Cmd+Shift+N | 新建聊天 |
| Cmd+, | 设置 |
| Cmd+F | 终端历史搜索 |
| Cmd+Control+B / J | 显示或隐藏书签栏 / 聊天栏 |
| Enter / Cmd+Enter | 发送聊天 |
| Option+Enter | 换行 |
| Cmd+C / Cmd+V | 终端复制 / 粘贴 |

## 数据与隐私

- 项目源码不包含账户、密钥、真实聊天、SSH 配置或终端记录。
- 登录数据、API Key 和 SSH 密码以明文 JSON 保存到 `~/Library/Application Support/TermGPT/credentials.json`，目录权限 0700、文件权限 0600。字段为 `chatGPT`、`apiKey` 和按书签 UUID 关联的 `sshPasswords`；采用原子写入，损坏配置不会被静默覆盖。此文件仅供本机使用，不提交 GitHub、不导出、不放入发行包。
- SSH 认证组件从该 JSON 配置读取对应密码，不通过参数或环境传递密码。主机指纹需人工确认；加密私钥口令和任意 OTP 提示建议使用 SSH Agent / 手工登录。
- v0.4 不读取或自动迁移旧钥匙串记录。ChatGPT 需重新连接一次，API Key 和已保存 SSH 密码需重新填入；之后保存到 JSON。原有书签、文件夹、聊天和设置保留。
- 设置、书签及可选聊天保存在 `~/Library/Application Support/TermGPT/workspace.json`，目录权限 0700、文件权限 0600。关闭保存聊天后，持久化文件不再包含聊天。
- OAuth 使用 PKCE、state、nonce 和签名验证；回调仅监听 127.0.0.1，有五分钟超时。Disconnect 清除本地令牌并尝试远程撤销。不会读取 ChatGPT 网站历史聊天。
- 终端回滚在内存中保存，最多 10,000 行；发送过的上下文可能随聊天保存。导出默认脱敏。
- 脱敏仅匹配常见格式，不保证识别所有秘密。关闭脱敏意味着所选供应商会接收到原文。
- 风险分类仅提供有限保护，不能证明命令安全或终端当前处于 Shell 提示符。

## 测试

```bash
./scripts/test-with-fixture.sh
./scripts/verify-package.sh
```

第一条检查 Python 3/curl 并启动仅监听本机的固定 SSE 模拟服务，运行测试后关闭服务；不使用真实密钥。测试覆盖 PTY、上下文、SSH 参数、JSON 凭据读写与文件权限、脱敏设置、输入快捷键、OAuth 回调、PKCE、签名验证及配置迁移。第二条独立解压发行 ZIP，检查 plist、架构和签名。

自动测试不等于真实账户、真实模型、所有 macOS 版本或真实 SSH 主机都已验证。本地开发记录、测试输出和构建缓存不提交至开源仓库。

## 脚本与目录

| 路径 | 作用 / 使用 |
| --- | --- |
| `scripts/migrate-bilingual-ui.py` | v0.4 一次性双语界面迁移；检查 Python 3 与源码，已迁移时不改文件；正常构建无需运行 |
| `Sources/TermGPTSSHAskpass` | OpenSSH 密码认证与主机指纹确认组件 |
| `Sources/TermGPT` | 界面、PTY、聊天、OAuth、存储和输入框 |
| `Tests/TermGPTTests` | 合成数据与本机集成测试 |
| `Assets` | 图标源 PNG 及 icns 生成说明 |
| `Vendor/SwiftTerm` | 已固定的终端库及原始许可证 |
| `scripts/check-environment.sh` | 使用前检查系统与依赖 |
| `scripts/audit-release.py` | Python 3 检查 ARM/Intel ZIP 文件白名单、个人路径、典型凭据及图标元数据，失败时停止发布 |
| `scripts/build-release.sh` | 从干净 Git 提交在临时目录构建 ARM/Intel 包，检查架构、签名和个人路径，生成校验和 |
| `scripts/build.sh` | 编译 release 后打包 |
| `scripts/package-app.sh` | 从 release 程序组装、签名 App 和 ZIP |
| `scripts/run.sh` | 启动 App，缺少 App 时先构建 |
| `scripts/test.sh` | 检查环境并执行 XCTest |
| `scripts/test-with-fixture.sh` | 自动启动和清理本机模拟 API 后测试 |
| `scripts/mock-provider.py` | 手动启动固定 SSE 服务，用 Ctrl+C 停止 |
| `scripts/toolchain.sh` | 供构建/测试引用，定位宏插件、XCTest 及缓存 |
| `scripts/make-icon.sh` | 检查 sips/iconutil，生成 icns，然后重新 build |
| `scripts/update-provider-ui.py` | 历史源码迁移辅助，已应用时退出，正常使用无需运行 |
| `scripts/export-public.py` | 按白名单生成独立开源目录，默认输出到项目同级的 TermGPT-open-source |
| `scripts/audit-public.py` | 检查发布目录或 Git 跟踪文件中的个人路径、凭据模式、禁止文件和图标元数据；有发现则退出失败 |

所有处理脚本均保存在项目内。运行 Python 脚本前用 `python3 --version` 检查 Python 3；发布脚本还检查 Git、输入目录和输出路径。

## 开源发布

```bash
python3 --version
python3 scripts/export-public.py
cd ../TermGPT-open-source
python3 scripts/audit-public.py
```

ICNS 可能由系统工具添加元数据，因此发布只包含经检查的 PNG，构建时生成 ICNS。

导出不复制 `.build`、`dist`、日志、原始需求书、本地验证记录、用户配置、截图或任何 Git 历史。发布目录使用独立 Git 仓库；不要在上级目录执行 `git add .`。审查脚本不是专业秘密扫描器或安全认证，发布前仍应人工查看最终文件清单与差异。

## 范围与许可证

尚未实现分屏、多终端联合上下文、Agent 循环、精确命令块、MCP、SQLite、多层文件夹和原生 Anthropic/Gemini 协议。

TermGPT 使用 MIT License。SwiftTerm 上游 v1.9.0，commit `8840e3596739adfe9599c0e7fff89f4fa88bedcf`，保留其 MIT License 和版权声明；本地 Package.swift 简化为 macOS 库，无远程依赖；上游调试路径改为动态主目录，避免个人绝对路径。图标由 AI 生成，包含终端提示符和星光，不包含第三方商标。项目不是 OpenAI 官方产品。

维护者构建双架构发行包：先提交源码，再运行 `./scripts/build-release.sh`。脚本检查 Git、Python 3 和构建环境，不读取账户或运行配置。

- 聊天和书签整行均可点击选择/连接，三个点菜单独立操作；切换聊天默认显示最下方消息，生成过程中仍不强制滚动。

### SFTP 文件面板

选中 SSH 终端标签页，点击顶部工具栏的文件夹按钮（或右键 SSH 标签页 → SFTP 文件）。面板固定连接打开时的书签主机，之后切换标签页不会改变文件目标。本地 Shell 不提供此按钮；在本地终端里手动执行 SSH 的连接无法自动识别。

输入远端路径、点击上级目录/刷新，或双击目录浏览。选中文件后点击下载（也可双击文件），选择本地保存位置；上传文件按钮选择单个本地文件，上传到当前远端目录。同名替换会确认。传输显示已确认的字节进度，失败原因显示在窗口中；取消只停止 SFTP，不关闭终端。

复用系统 OpenSSH、SSH config/Agent、书签私钥或 JSON 中保存的密码。未保存的密码、私钥口令或交互验证使用临时安全输入框，不保存手动输入的值；未知主机指纹仍需确认。不增加跳板机功能。

上传先写 `.partial` 临时文件，再改名；覆盖同名文件需要服务器支持 OpenSSH POSIX rename 扩展。新上传文件权限为 0600。下载使用本地 0600 临时文件，成功后才替换所选目标。连接中断可能残留远端 `.partial` 文件，可手动清理。暂不支持目录递归传输和远端编辑，文件名需为 UTF-8。

开发验证：`./scripts/test-isolated.sh` 先检查环境，将源码复制到临时目录运行测试，结束后自动清理，适用于同步目录引起文件时间戳变化的情况。SFTP 集成测试使用 `/usr/libexec/sftp-server` 和临时测试文件，不读取保存的凭据或访问远端主机。也可通过 `TERMGPT_TEST_BUILD_DIR=/private/tmp/termgpt-tests ./scripts/test.sh` 指定构建缓存。

### sz / rz（ZMODEM）

远端执行 `sz 文件名` 下载到 Mac，会弹出本地保存目录选择框；远端执行 `rz` 上传，会弹出本地文件选择框，可多选。远端需要安装自己的 rz/sz，Mac 辅助工具已内置，不需要 Homebrew。也支持在本地 Shell 中手动 SSH 登录后的传输。

协议数据不会作为终端文字渲染。传输期间暂停普通键盘输入和 AI 命令操作，终端底部显示进度、错误和取消传输按钮。下载先接收到私有临时目录，成功后移动到所选位置，同名文件添加数字后缀，不覆盖原文件。取消会删除部分本地下载；批量失败后请重试，不支持递归传输目录。

内置 lrzsz 0.13.1 是单独的 GPL-2.0-or-later 辅助程序，完整对应源码、许可与编译说明位于 `Vendor/lrzsz`。`./scripts/build-zmodem.sh arm64` 检查环境并编译工具，Intel 使用 x86_64；`python3 scripts/test-zmodem.py .build/zmodem-arm64` 验证实际协议传输，不访问真实远端。

### VNC 与 RDP 桌面

远程桌面默认根据中间区域自动请求分辨率，调整窗口或侧栏宽度时会随之更新。连续变化合并为 300 毫秒后的一次请求，采用逻辑点保证 Retina 屏幕上的文字易读，范围为 200×200 至 4096×2160。RDP 使用 Display Control 通道，VNC 在服务器提供屏幕布局时使用 ExtendedDesktopSize。不支持或不允许调整分辨率的服务器保持原分辨率，并等比例缩放显示；切换标签只调整当前可见桌面。

服务端首帧完全为黑色时，TermGPT 会发送一次短暂的鼠标移动（**不点击、不按键**），并请求完整刷新以唤醒闲置显示。连接组件明确设置用户目录和临时目录；状态、证书等小数据包立即处理，不等待缓冲区填满。

连接日志自动保存在 `~/Library/Application Support/TermGPT/Logs/`，点击桌面顶部的文档放大镜按钮即可打开。记录连接阶段、协议错误、证书选择和组件退出码；不记录密码、配置中的主机/用户名/域、剪贴板内容或画面。文件仅当前用户可读写，每份最多 2 MiB，保留最近 20 次连接，不自动上传。

只读检查可在项目目录运行 `python3 scripts/diagnose-desktop.py`（需要 Python 3.9+）：检查书签的 TCP 端口和协议握手，不读取密码、不登录远程系统。需要验证真实连接时运行 `python3 scripts/probe-desktop-bookmarks.py /Applications/TermGPT.app/Contents/MacOS/TermGPTRemoteDesktop --app-environment`，使用本机保存的凭据，每个桌面尝试一次；收到非黑画面或 RDP 证书提示即停止，不自动信任证书，不发送按键、点击或剪贴板。组件可能移动鼠标以唤醒初始黑屏。输出只含书签 ID、脱敏协议信息和画面是否全黑的判断，不保存像素。`--minimal-environment` 可复现旧版组件运行环境，用于回归排查。

端口拒绝连接应检查地址、端口和服务器是否运行；认证失败应核对服务器认证模式及登录信息。RDP 的未受信任证书通过原生弹窗确认，顶部也提供证书按钮，核对身份后可选择“仅本次信任”。崩溃时同时查看 macOS“控制台 → 崩溃报告”里的 TermGPT 报告。旧版本书签地址中误粘贴的控制字符会在加载时自动清理。

在“连接书签”旁点击 **+**，选择 **VNC** 或 **RDP**，填写主机、端口和登录信息。默认端口为 VNC 5900、RDP 3389；RDP 可填写域。书签沿用文件夹管理、修改/重命名和删除菜单，旧 SSH 书签兼容。点击书签所在行后，桌面在中间标签页打开，支持关闭、拖动排序、关闭右侧和关闭全部。

桌面支持键盘、鼠标、滚轮和画面缩放。RDP 建立 1440×900 会话，接收画面上限为 4096×2160；上方提供 **Ctrl+Alt+Del** 按钮。可在书签中关闭剪贴板同步；启用时仅当前桌面标签页同步文本，上限 1 MiB。RDP 支持 Unicode；VNC 中文等 Unicode 文本需要服务器支持扩展剪贴板，传统 VNC 仅支持 Latin-1 文本。剪贴板文件和图片不传输。

RDP 使用 TLS/NLA，遇到不受信任的证书会展示主机、颁发者和指纹，可选择“仅本次信任”“始终信任”或“取消”。始终信任将 SHA-256 指纹保存到本机限制权限的 `credentials.json`，绑定当前书签的主机与端口；完全匹配时自动通过，证书变化时重新询问。删除书签也会删除对应的信任记录。传统 VNC 密码认证不加密桌面流量，请在可信网络或安全隧道中使用。密码保存到本机限制权限的 JSON 凭据文件，不使用钥匙串。SFTP 和 AI 命令执行仅适用于终端标签页，不会发送到桌面。

本地安装已构建的版本：先退出 TermGPT，再运行 `./scripts/install-local-release.sh /安装包绝对路径/TermGPT-macOS-arm64.zip`（Intel Mac 使用 Intel 安装包）。脚本仅适用于 macOS，先检查环境、架构和签名，再原子替换 `/Applications` 中的应用；需要该目录写入权限，保留用户配置。

无需外部桌面客户端或 Homebrew 运行库。客户端库、构建环境和许可证说明见 [Vendor/RemoteDesktop/README.md](Vendor/RemoteDesktop/README.md)。`scripts/build-remote-desktop.sh` 构建 ARM/Intel 桌面组件；`scripts/test-remote-desktop.py`、`scripts/test-rdp-desktop.py` 使用合成本机服务验证协议，不读取真实凭据。不包含音频、磁盘映射、网关、多显示器或文件剪贴板功能。

独立桌面组件采用 GPL-3.0-or-later，主程序保持 MIT 许可证。发行版同时提供 `TermGPT-RemoteDesktop-source.tar.gz`，包含固定版本的完整上游源码及组件/构建源码；`python3 scripts/package-remote-source.py` 校验后重新生成该源码包。RDP 内使用 Windows 快捷键，Command 映射为 Control，便于复制/粘贴。

仅修复桌面组件时，可运行 `./scripts/repack-desktop.sh arm64`（Intel 使用 `x86_64`），在已有 0.6.0 安装包中重新构建组件、签名并检查架构与隐私；脚本先检查环境和包版本，再替换 ZIP。完整发行构建仍使用 `scripts/build-release.sh`。

### WEB 书签

HTTP Basic/Digest 身份验证会弹出用户名和密码框，取消后终止验证；默认只用于浏览器会话；勾选“保存密码”后保存到本机权限受限的 credentials.json，按协议、主机、端口、认证域和方式隔离，下次自动登录。本地测试页面 `/auth` 使用模拟用户名和密码 `fixture` / `fixture`。

打开书签时按书签 ID 检查现有标签。没有对应标签时直接打开；已有时可选择“切换到已有标签”“打开新标签”或“取消”。适用于所有连接类型；切换优先保留当前匹配标签，否则选择第一个匹配标签。

内置网页输入框默认关闭拼写检查、自动纠正和自动大写，包含动态输入框和子页面；macOS 15 及以上同时关闭系统书写工具。网站自身的提示和输入法候选词仍由网站或输入法控制。

新增连接书签时选择 **WEB**，输入名称和完整的 HTTP 或 HTTPS URL，选择文件夹后保存。点击书签，在中间标签页内浏览网页。编辑、删除、移动文件夹沿用现有菜单；标签页支持关闭和拖动排序。网页工具栏提供前进、后退、刷新和可编辑地址，各标签保留独立浏览历史。网页不作为终端上下文或 SFTP 目标。使用 macOS 自带 WebKit，无需额外安装运行环境；网站登录会话由 WebKit 保存在本机，证书采用系统默认验证。

本地验证：先检查 `python3 --version`（需要 3.8 或更新），运行 `python3 scripts/webview-fixture.py`，使用打印的本地地址新增 WEB 书签，验证前进、后退、刷新、切换和关闭标签。Ctrl+C 停止测试服务。脚本仅在本机回环地址提供模拟页面，不读取个人文件。

网页导航和地址栏默认隐藏，旧配置升级后同样默认隐藏。在 **设置 → 显示网页地址栏** 开启并保存后显示前进、后退、刷新及地址框；关闭后网页主体占满面板，切换设置不会重新加载网页。

### 中文及 Unicode 终端输入

本地 Shell 和 SSH（包括密码登录）使用 UTF-8 字符环境，保留已有 UTF-8 语言设置，GUI 环境缺少 Unicode locale 时补充 `en_US.UTF-8`。认证提示可以使用 `LC_MESSAGES=C`，交互终端不再强制 `LC_ALL=C`。升级后请重连已有 SSH 标签页。远端 SSH 服务仍需接收或自行配置 UTF-8 locale；远端 Shell 启动文件可能覆盖它。SFTP 和传输组件的协议语言环境与交互终端独立。

本地复现：运行 `python3 scripts/test-unicode-pty.py`（macOS、Python 3.8+、`/bin/zsh`）。脚本先检查环境，在临时 HOME 中启动隔离 zsh PTY，对照 C 和 UTF-8 环境，检查中文输入显示及 Shell 接收内容，并清理临时文件；不访问 SSH 主机或个人 Shell 配置。

### 拖选终端历史内容

选中文本并将鼠标拖到终端可见区域的下边缘或上边缘，终端会持续滚动并扩展选区，便于跨屏复制历史内容。松开鼠标或移回中间区域立即停止。接管鼠标输入的终端程序继续使用原有鼠标报告行为。组件修改说明见 `Vendor/SwiftTerm/TERMGPT-PATCHES.md`，原生视图回归测试覆盖滚动和停止行为。

### 书签排序

书签菜单和文件夹右键菜单提供 **上移 / 下移**，分别调整当前文件夹内的书签顺序和文件夹列表顺序。移动书签到其他文件夹仍使用原有“移动到文件夹”菜单。顺序保存到现有 JSON 配置，重启后保留，SSH、VNC、RDP、WEB 行为一致。

已经验证但尚未发布的安装包，仅修正 Swift 界面且原生组件和版本信息不变时，可以运行 `scripts/rebuild-swift-release.sh 已验证安装包的构建提交`。脚本检查运行环境、源码提交、原生源码/资源/打包元数据未变、旧包校验值及签名，隔离重建 ARM 和 Intel Swift 程序，并重新审计 ZIP；沿用已验证的原生组件及版本信息。原生代码、资源、依赖、打包元数据或版本号变化时必须使用完整 `scripts/build-release.sh`。
