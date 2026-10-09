# 开发与脚本指南

[English](DEVELOPMENT.md) · [主 README](../README.zh-CN.md)

在仓库根目录运行脚本。所有处理脚本位于 `scripts/`，使用前检查环境：

```bash
./scripts/check-environment.sh
python3 --version
cmake --version
```

需要 macOS 13+、Swift 5.9+、Command Line Tools 和系统 SSH/zsh。桌面组件需要 CMake 3.20+、Python 3.12+、make 和 Perl；依赖下载到忽略的 `.build` 并校验哈希。XCTest 需要 `/Applications/Xcode.app` 下的完整 Xcode。脚本不接受 Xcode 许可或替换默认工具链。Python 模拟服务需要 3.8+，桌面诊断需要 3.9+；详见各脚本用法和依赖检查。

## 常用流程

```bash
./scripts/build.sh
./scripts/run.sh
./scripts/test-with-fixture.sh
./scripts/verify-package.sh
```

输出为 `dist/TermGPT.app` 和当前架构 ZIP。模拟 API 只使用回环地址和合成数据。测试覆盖凭据/权限、PTY 输入、拖选滚动、书签顺序、上下文、OAuth 和界面设置。独立检查验证解压、plist、架构和签名，不代表公证或真实远端兼容性。

同步目录的时间戳异常可使用 `./scripts/test-isolated.sh`。更新后重连 SSH，才能加载 UTF-8 环境；远端 Shell 可能覆盖或拒绝转发的 locale。

## 发布

更新 `scripts/package-app.sh` 中版本号和构建号，提交干净工作区，再运行：

```bash
./scripts/build-release.sh
python3 scripts/audit-public.py --tracked
python3 scripts/audit-release.py dist/TermGPT-macOS-arm64.zip dist/TermGPT-macOS-x86_64.zip
```

发布脚本将提交源码快照放到 `/private/tmp`，编译双架构、签名、审计，打包桌面对应源码并生成 `dist/SHA256SUMS`。检查文件清单和差异，将两个 ZIP、源码包、校验和上传到草稿 Release；确认上传哈希一致后再公开。不要上传运行配置、凭据、日志或截图。审计是有限检查，不是安全认证。

本机安装：先退出应用，运行 `./scripts/install-local-release.sh /安装包绝对路径/TermGPT-macOS-arm64.zip`，Intel 使用对应包。脚本检查环境、架构和签名，替换 `/Applications/TermGPT.app` 并保留用户配置；重启会断开会话。

## 网页模拟验证

```bash
python3 scripts/webview-fixture.py
```

使用打印的回环地址新建临时 WEB 书签，验证导航、拼写纠正、重复标签选择，以及 `/auth` 的 Basic Auth。模拟用户名/密码都是 `fixture`。Ctrl+C 停止服务，并删除临时书签。测试保存密码后运行：

```bash
python3 scripts/webview-fixture.py --clear-saved-auth "$HOME/Library/Application Support/TermGPT/credentials.json"
```

只清理该回环测试的精确模拟凭据，不打印其他条目。

## 脚本索引

| `scripts/` 下脚本 | 作用与用法 |
| --- | --- |
| `check-environment.sh` | 检查 macOS、工具链、SSH/zsh 和终端依赖 |
| `build.sh`、`run.sh` | 当前架构构建/打包；启动，缺少应用时先构建 |
| `package-app.sh` | 组装、签名、压缩 release 程序，可传入程序路径 |
| `build-release.sh` | 从干净提交完整构建 ARM/Intel，检查隐私和安装包 |
| `verify-package.sh` | 独立检查 ZIP，可指定 ZIP 和预期架构 |
| `install-local-release.sh` | 检查并安装本地 ZIP，需要 Applications 写入权限 |
| `toolchain.sh` | 构建/测试引用，定位缓存、宏插件和 XCTest |
| `make-icon.sh` | 检查 sips/iconutil，从 PNG 生成 ICNS |
| `test.sh`、`test-with-fixture.sh` | XCTest；可自动启动/清理回环 AI 模拟服务 |
| `test-isolated.sh` | 从同步目录复制源码快照后测试 |
| `mock-provider.py` | 固定 SSE 模拟服务，Ctrl+C 停止 |
| `webview-fixture.py` | 网页/Basic Auth 模拟服务及精确测试凭据清理 |
| `test-unicode-pty.py` | 临时 HOME 中对照 C/UTF-8 zsh 显示和接收内容 |
| `build-zmodem.sh` | 构建 rz/sz，传入 arm64 或 x86_64 |
| `test-zmodem.py` | 使用模拟文件测试二进制、中文、空文件和多文件；传入组件目录 |
| `fetch-remote-deps.py` | 下载固定版本桌面依赖并校验哈希 |
| `build-remote-desktop.sh` | 构建桌面组件，可指定架构、输出目录和测试服务器开关 |
| `test-remote-desktop.py`、`test-rdp-desktop.py` | 回环模拟协议测试，不读取真实凭据 |
| `diagnose-desktop.py` | 读取书签地址并检查端口/握手，不读密码、不登录 |
| `probe-desktop-bookmarks.py` | 显式真实连接诊断，使用已保存凭据；传入组件路径和 --app-environment；不点击/按键/传剪贴板，可能移动 VNC 鼠标唤醒画面 |
| `package-remote-source.py` | 校验并打包对应上游、组件和构建源码 |
| `audit-public.py`、`audit-release.py` | 源码/安装包白名单、个人路径、凭据模式和元数据检查 |
| `export-public.py` | 白名单源码导出，排除运行数据、构建输出和历史 |
| `rebuild-swift-release.sh` | 已验证但未发布包的同版本 Swift 修复；传入原构建提交，拒绝原生代码/资源/元数据变化 |
| `repack-desktop.sh`、`repackage-desktop-fix.sh` | 历史桌面修复流程，按脚本检查版本和输入；新发布使用完整构建 |
| `update-provider-ui.py`、`migrate-bilingual-ui.py` | 历史一次性迁移，正常构建无需运行 |

## 源码与依赖

- `Sources/TermGPT`：界面、终端、网页/桌面会话、AI、多语言和 JSON 存储。
- `Sources/TermGPTSSHAskpass`：OpenSSH 密码和主机指纹组件。
- `Tests/TermGPTTests`：合成数据单元与本机集成测试。
- `Assets`：图标源文件和生成说明。
- `Vendor/SwiftTerm`：固定终端库和修改说明。
- `Vendor/lrzsz`、`Vendor/RemoteDesktop`、`Native`：独立传输/桌面组件、许可证和构建定义。

协议限制、依赖许可和模拟验证详见[桌面组件说明](../Vendor/RemoteDesktop/README.md)。真实主机诊断与合成测试不同；自动检查不代表所有账户、远端或实体 Intel Mac 已验证。
