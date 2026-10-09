# TermGPT

**English** | [简体中文](README.zh-CN.md)

A native macOS workbench for terminals, an AI assistant, remote desktops and embedded web pages. Built with SwiftUI, AppKit, SwiftTerm and WebKit.

## Download

Get the latest version from [GitHub Releases](https://github.com/wangyeye/TermGPT/releases/latest).

| Mac | Package |
| --- | --- |
| Apple Silicon (M-series) | `TermGPT-macOS-arm64.zip` |
| Intel | `TermGPT-macOS-x86_64.zip` |

Requires **macOS 13+**. Extract the ZIP and move `TermGPT.app` to Applications. No Homebrew or separate remote-desktop client is needed to run the app. Releases include `SHA256SUMS` and corresponding desktop-helper source.

Packages are ad-hoc signed, **not Developer ID signed or notarized**. Intel builds are cross-compiled and architecture-checked; physical Intel testing is pending.

![TermGPT icon](Assets/AppIcon.png)

## Features

| Area | Capabilities |
| --- | --- |
| Terminal | Local PTY, interactive SSH, ANSI rendering, Unicode input, scrollback and edge scrolling during text selection |
| Bookmarks | SSH / VNC / RDP / WEB, folders, edit/rename/delete, Move Up/Down menus and persistent order |
| Tabs | Center-pane connections, drag ordering, close all and close tabs to the right |
| AI assistant | ChatGPT, OpenAI API, Ollama, LM Studio and compatible endpoints; streaming, context selection and command actions |
| File transfer | SFTP browsing/upload/download; rz/sz ZMODEM transfers |
| Remote desktop | Embedded VNC/RDP, adaptive resolution, text clipboard, remote audio and certificate trust choices |
| Browser | WebKit tabs, optional address bar, Basic/Digest authentication and optional saved passwords |
| Appearance | System/light/dark theme, English/Chinese UI and persistent sidebar layout |

### Connection diagnostics, audio and reconnect

Right-click an SSH/RDP/VNC tab for **Reconnect**, **Automatically Reconnect** and **Connection Diagnostics**. Manual reconnect reuses the tab after a connection ends. Automatic reconnect is off by default, applies to that tab only and makes at most three attempts after an unexpected disconnect, at 3/6/9-second intervals. Authentication, permission and certificate errors stop retries. Closing the tab or disabling the option cancels pending attempts; these temporary choices are not saved.

Diagnostics check the TCP port without logging in. SSH config aliases are resolved with the system `ssh -G`. Reachability does not validate credentials or protocol compatibility. RDP errors and VNC/SSH failure output are classified into network, DNS, authentication, certificate/protocol and permission guidance where evidence permits. Desktop failures offer Diagnose and Reconnect buttons. Connection logs remain local and do not record passwords, clipboard or frame content.

Desktop tab menus show audio state and **Mute/Unmute**. Waiting for server audio does not prove the server has its audio modules. VNC bell-only status means continuous audio has not been negotiated. Muting affects that connection, including VNC bells, and is retained across manual reconnect in the same tab. No desktop top status bar is added.

### Find and open connections

Search the sidebar by bookmark name, address, protocol or folder. Multiple words must all match; matching folders expand temporarily without changing bookmark order. **⌘P** opens Quick Open from any layout: type to filter, use arrows and Enter, or click a row. Open tabs switch directly; bookmark entries use the existing duplicate-tab choice. Esc closes the window. The sidebar’s Recent Connections contains the last ten opened/switched bookmarks, stored as IDs in `workspace.json`; it includes connection attempts, not only successful authentication. Clear removes history without deleting bookmarks; renamed bookmarks update automatically and deleted bookmarks disappear.

## Quick start

1. Open **Local Shell**, or click **+** beside Connection Bookmarks.
2. Choose SSH, VNC, RDP or WEB, enter a name and connection details, then save. WEB requires a full HTTP/HTTPS URL. SSH supports config/Agent, saved passwords or private keys; VNC/RDP support saved credentials.
3. Click anywhere on the bookmark row to connect. If that bookmark already has an open tab, choose **Switch to Existing Tab**, **Open New Tab** or Cancel. Matching uses bookmark identity, not URL equality.
4. Use `…` to edit/delete, change folders or move a bookmark up/down. Folder context menus provide Move Up/Down. Folder management creates, renames and deletes folders; deleting a folder moves its bookmarks to Unclassified.
5. Open **Settings** to connect an AI provider, choose language/theme, set redaction or show the web address bar. Language follows the system by default: Chinese uses Chinese; unsupported languages use English.
6. Top-right layout controls show/hide bookmarks and the AI assistant. SFTP has a separate folder button.

### AI assistant

Choose **Continue with ChatGPT** in Settings. Account, plan, allowance and model access come from the service. OpenAI API is a separate option under Advanced / Other Providers. Start Ollama or LM Studio before entering an available local model.

Chat shows the submitted context source separately from the active command destination. Context can be Auto, Off, selected text, recent lines or the session, and can be pinned. AI never executes commands by itself. Shell-labelled code blocks provide Copy/Insert/Run; logs, quotations and other code offer Copy only. Insert does not press Enter. Commands needing confirmation use Confirm & Run without typing RUN.

Streaming replies do not force-scroll: you can read older messages and copy commands while generation continues. Switching chats opens the latest messages. Chats support rename/delete, optional local history and export. Redaction is applied automatically according to Settings without an extra dialog.

### Web bookmarks

Right-click a WEB tab → **Close Other Tabs** to keep that tab and close all other central tabs, including terminal and remote-desktop connections.

Right-click a browser tab and choose **Force Reload** to reload the page from the server, bypassing cached content.

The address/navigation bar is **hidden by default**. Enable Show Web Address Bar in Settings for Back, Forward, Reload and the URL field; toggling does not reload the page.

HTTP Basic/Digest challenges open a username/password dialog. Select **Save Password** to reuse credentials after restarting. Credentials are isolated by scheme, host, port, realm and authentication method. Standard username/password login forms ask whether to save the login when you submit. Choosing Save and Autofill fills that exact website origin on later visits without submitting the form. Dynamic forms are supported; third-party frames, passkeys, multi-step or nonstandard controls may need manual input. JavaScript password prompts (including noVNC) support optional saved, prefilled passwords.

Untrusted HTTPS certificates show the host, certificate subject and SHA-256 fingerprint. Choose **Trust Once**, **Always Trust** or Cancel. Always Trust saves the fingerprint for that host/port; a changed certificate prompts again. Other hosts retain normal certificate validation.

Web fields disable spellchecking, automatic correction and capitalization; macOS 15+ system Writing Tools are also disabled. Website suggestions and input-method candidates remain controlled by the website/input method. Sessions and cookies are stored locally by WebKit.

### File transfers

- **SFTP:** select a bookmarked SSH tab, then use the toolbar folder button or the tab's SFTP context menu. Browse paths, upload one file or download a selected file, with progress, errors and cancellation. The window stays attached to its original host when tabs change. SSH started manually inside Local Shell cannot be detected for SFTP.
- **ZMODEM:** run `sz filename` remotely to choose a local download folder, or `rz` to choose upload files. The remote host needs rz/sz; Mac helpers are bundled. Keyboard and AI command actions pause during transfer.
- SFTP overwrites require confirmation. Transfers use staging files; interrupted uploads may leave a remote `.partial` file. Recursive directory transfers and remote editing are not included.

### VNC and RDP

Desktops open in center tabs. Resolution follows the visible pane when the server supports resizing; otherwise the framebuffer scales proportionally. RDP uses TLS/NLA and offers Trust Once / Always Trust / Cancel. Persistent trust pins a certificate to the bookmarked host/port; changes prompt again.

Clipboard synchronization is optional, text-only, limited to the selected desktop and 1 MiB. RDP supports Unicode; VNC Unicode requires extended clipboard support. Traditional VNC authentication does not encrypt desktop traffic. Drive mapping, gateways, multiple monitors and file/image clipboard are not included.

Remote audio plays through the Mac’s selected output automatically. RDP requires server-side audio redirection (xrdp also needs its audio modules). VNC supports the standard bell and continuous audio from servers advertising the QEMU Audio extension; ordinary VNC servers without that extension cannot stream sound. Microphone forwarding is not included.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Cmd+T / Cmd+W | New / close terminal tab |
| Cmd+Shift+N | New chat |
| Cmd+, | Settings |
| Cmd+F | Terminal history/search |
| Cmd+Control+B / J | Toggle bookmarks / AI assistant |
| Enter or Cmd+Enter | Send chat; IME candidate confirmation does not send |
| Option+Enter | New line in chat |
| Cmd+C / Cmd+V | Terminal copy/paste |

## Local data and privacy

Files under `~/Library/Application Support/TermGPT/`:

| File | Contents |
| --- | --- |
| `workspace.json` | Bookmarks, folders, order, preferences and optional chat history |
| `credentials.json` | ChatGPT tokens, API key, saved connection/web passwords and certificate pins |
| `Logs/` | Local remote-desktop diagnostics |

Credentials are **plain JSON**, with directory/file permissions 0700/0600 and no Keychain prompts. Keep these files private. Writes are atomic; malformed credentials are not silently overwritten. Old Keychain records are not automatically migrated.

Source and release packages exclude personal configuration, credentials, chats, screenshots and logs. Diagnostics are not uploaded automatically. AI requests share selected messages/history/context with the chosen provider. Redaction defaults to on but cannot identify every secret; export redacts by default. WebKit maintains separate local website storage.

VNC/RDP desktops fill the tab without a top status bar. Right-click the desktop tab for connection status, logs, certificate verification and RDP Ctrl+Alt+Del. Connection and failure messages appear over the desktop until connected.

Desktop logs omit passwords, configured host/user/domain values, clipboard and pixels; at most 20 sessions are retained, 2 MiB each. Use the tab's log menu and macOS Console crash reports to investigate failures.

## Build, test and release

See the [development and script guide](docs/DEVELOPMENT.md) for prerequisites, all script purposes, testing, diagnostics and release instructions.

```bash
./scripts/check-environment.sh
./scripts/build.sh
./scripts/run.sh
```

Build requires macOS 13+, Swift 5.9+, Command Line Tools and system SSH/zsh. Desktop helpers also require CMake 3.20+, Python 3.12+, make and Perl. Tests require full Xcode/XCTest. No Rust, Node or npm is needed.

## License and limits

The main app is [MIT licensed](LICENSE). SwiftTerm retains MIT notices; separate lrzsz helpers use GPL-2.0-or-later and the desktop helper uses GPL-3.0-or-later. Releases provide desktop source in `TermGPT-RemoteDesktop-source.tar.gz`. See [desktop dependency notes](Vendor/RemoteDesktop/README.md), [lrzsz source](Vendor/lrzsz) and [SwiftTerm patches](Vendor/SwiftTerm/TERMGPT-PATCHES.md).

Not implemented: split terminals, nested bookmark folders, combined multi-terminal AI context, an autonomous agent loop, MCP or native Anthropic/Gemini protocols. Availability depends on the provider and remote server. TermGPT is not an official OpenAI product.
