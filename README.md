# TermGPT

**English** | [简体中文](README.zh-CN.md)

A native macOS terminal and AI chat workbench built with SwiftUI, AppKit and SwiftTerm. Terminals run independently; AI receives only the context selected for a request.

## Download

Download macOS 13+ packages from [GitHub Releases](https://github.com/wangyeye/TermGPT/releases):

- Apple Silicon: `TermGPT-macOS-arm64.zip`
- Intel Mac: `TermGPT-macOS-x86_64.zip`

Extract the ZIP and move `TermGPT.app` into Applications. Releases include `SHA256SUMS`. Apps use ad-hoc signing and are not Developer ID signed or notarized. Signature verification does not imply Gatekeeper approval. Intel builds are cross-compiled and architecture-checked; physical Intel Mac testing is pending.

![TermGPT icon](Assets/AppIcon.png)

## Features

- Real PTY local terminals with ANSI rendering, scrollback, interactive SSH and programs such as vim/top.
- Multiple terminal tabs and editable SSH bookmarks, folders, password or private-key authentication through system OpenSSH.
- Multiple chats with rename/delete, streaming replies, cancellation, optional local history and export.
- ChatGPT as the preferred provider; OpenAI API, Ollama, LM Studio and compatible endpoints under Advanced / Other Providers.
- Top-right layout controls to show/hide bookmarks and chat, focus on the terminal, or restore the default layout. Layout persists.
- English and Chinese UI. Choose Follow System, English or 中文. Chinese system languages use Chinese; other system languages fall back to English.
- System, light and dark appearance across the interface, dialogs, chat input and terminal.
- Context modes: Auto, Off, selected text, last 50/200 lines or the entire session, with pinned context.
- Terminal context menu: Ask AI, Explain, Fix and Generate command.
- Code actions: copy, insert or run. Low-risk single-line commands run directly; unknown/high-risk commands require Confirm & Run without typing RUN.
- Optional automatic redaction before sending, without a confirmation dialog.
- ChatGPT login data, API keys and saved SSH passwords stored in local JSON configuration without Keychain prompts.

## Check the environment and build

Requires macOS 13+, Swift 5.9+, Xcode Command Line Tools, system SSH and zsh. Tests require full Xcode with XCTest; scripts locate the standard `/Applications/Xcode.app`. No Rust, Node or npm is needed. SwiftTerm is vendored.

```bash
cd TermGPT
./scripts/check-environment.sh
./scripts/build.sh
./scripts/run.sh
```

Output: `dist/TermGPT.app` and an architecture-specific ZIP. Scripts stop if dependencies are missing; they do not change the default toolchain or accept Xcode licenses. Packaging signs in a temporary directory to avoid file-sync metadata. If your checkout uses file synchronization, extract the ZIP into a local directory before launching.

## Use

1. Use the local shell immediately. Add SSH bookmarks with `+`; their `…` or context menu supports edit, delete and move. The folder button opens folder management. Authentication can use SSH config / Agent, a saved password or a private key. No jump-host feature is provided, and old jump-host fields are ignored.
2. Open Settings and choose Continue with ChatGPT. Sign in and authorize plan usage in the system browser. The service determines plan, allowance and model access; missing plan names are never guessed to be Plus.
3. Configure other providers under Advanced / Other Providers. OpenAI API needs its own key and billing. Ollama defaults to `http://127.0.0.1:11434/v1`; LM Studio to `http://127.0.0.1:1234/v1`. Start the local service and enter an available model name.
4. Enter sends chat; Option+Enter inserts a new line. Confirming an IME candidate does not send.
5. Rename or delete chats with `…` or their context menu. Custom names are preserved. Deleting the selected chat selects a neighbor; deleting the last creates a blank chat. These actions are disabled during a reply.
6. Select Context to control what is included. Auto is a heuristic; use Off or an explicit mode when you need precise control.
7. In Terminal & Privacy, select appearance and redaction. Redaction defaults to on. Turning it off sends messages, history and selected terminal context unchanged to the current provider.
8. The top-right left/right sidebar buttons control bookmarks and chat. The grid menu restores the default layout; the rectangle focuses on the terminal. Hiding chat keeps its history and any ongoing reply. Settings remains accessible through Cmd+,. Choose Language and Save to apply it immediately. User names, chat contents and terminal output are not translated.
9. AI never executes commands by itself. Insert does not send Enter. Run targets the visible terminal and clears the normal shell input line first. Do not run commands while the terminal is inside a password prompt, vim or another interactive program.

ChatGPT Auto chooses the first visible server model; it is not the ChatGPT website's automatic routing. OAuth and Responses use official interfaces, with availability and authorization controlled by the service. References: [sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions).

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Cmd+T | New terminal |
| Cmd+W | Close terminal and end its process |
| Cmd+Shift+N | New chat |
| Cmd+, | Settings |
| Cmd+F | Terminal history/search |
| Cmd+Control+B / J | Toggle bookmarks / chat |
| Enter / Cmd+Enter | Send chat |
| Option+Enter | New line |
| Cmd+C / Cmd+V | Terminal copy/paste |

## Data and privacy

- Source and release packages exclude accounts, credentials, real chats, SSH configuration and terminal logs.
- Credentials are stored as plain JSON in `~/Library/Application Support/TermGPT/credentials.json`, with directory/file permissions 0700/0600. It contains `chatGPT`, `apiKey` and `sshPasswords` keyed by bookmark UUID. Writes are atomic; malformed configuration is not silently replaced. This file must remain private and is excluded from Git/export/release packaging.
- The SSH helper reads the matching password from this JSON configuration, never from arguments or environment variables. Host verification remains manual. Use SSH Agent or manual authentication for encrypted key passphrases and arbitrary OTP prompts.
- v0.4 does not read or migrate old Keychain records. Reconnect ChatGPT and re-enter any API key or saved SSH password once; new credentials are saved in JSON. Existing bookmarks, folders, chats and preferences remain available.
- Preferences, bookmarks and optional chats are stored in `~/Library/Application Support/TermGPT/workspace.json`, with directory/file permissions 0700/0600. Disabling chat storage excludes chats from the persisted file.
- OAuth uses PKCE, state, nonce and signature verification. Its callback listens only on 127.0.0.1 and times out after five minutes. Disconnect removes local tokens and attempts remote revocation. ChatGPT website history is not read.
- Terminal scrollback stays in memory, up to 10,000 lines. Sent context can remain in saved chats. Export redacts by default.
- Redaction recognizes common formats, not every secret. Disabling it sends original content to the chosen provider.
- Command risk classification offers limited protection; it cannot prove a command safe or verify that the terminal is at a shell prompt.

## Test

```bash
./scripts/test-with-fixture.sh
./scripts/verify-package.sh
```

The first checks Python 3/curl, starts a loopback-only synthetic SSE provider, runs XCTest and cleans up the provider. No real keys are used. Coverage includes PTY, context, SSH arguments/JSON credentials and file permissions, redaction, input shortcuts, OAuth callbacks/PKCE/signatures, language fallback and preference migration. The second independently extracts a release ZIP and verifies plist, architecture and signature.

Automated checks do not establish compatibility with every account, model, macOS version or SSH host. Development logs, test output and caches stay outside the public repository.

## Source and scripts

| Path | Purpose / use |
| --- | --- |
| `Sources/TermGPT` | UI, localization, PTY, chat, OAuth, storage and input |
| `Sources/TermGPTSSHAskpass` | SSH password authentication and host verification helper |
| `Tests/TermGPTTests` | Synthetic unit and local integration tests |
| `Assets` | Icon source PNG and ICNS generation instructions |
| `Vendor/SwiftTerm` | Pinned terminal library and upstream license |
| `scripts/check-environment.sh` | Check OS and dependencies before use |
| `scripts/build.sh` | Build release executables and package |
| `scripts/package-app.sh` | Assemble, sign and ZIP a release app |
| `scripts/run.sh` | Launch the app; build first if missing |
| `scripts/test.sh` | Check environment and run XCTest |
| `scripts/test-with-fixture.sh` | Start/clean up the local mock API and test |
| `scripts/mock-provider.py` | Run the fixed SSE fixture manually; Ctrl+C stops it |
| `scripts/toolchain.sh` | Locate macro plugins, XCTest and build caches |
| `scripts/make-icon.sh` | Check sips/iconutil and generate ICNS before rebuilding |
| `scripts/update-provider-ui.py` | Historical provider UI migration; no normal build use |
| `scripts/migrate-bilingual-ui.py` | One-time v0.4 bilingual migration; checks source/Python 3 and stops if already applied; no normal build use |
| `scripts/export-public.py` | Create a fresh allowlisted source export, including both READMEs |
| `scripts/audit-public.py` | Read-only source checks for personal paths, credential patterns, excluded files and image metadata |
| `scripts/build-release.sh` | Build ARM/Intel from a clean commit, verify and generate checksums |
| `scripts/audit-release.py` | Verify release ZIP allowlists, personal paths, credential patterns and icon metadata; stop on findings |

All processing scripts live in this checkout. Run `python3 --version` before Python scripts. Release/export scripts also check Git, input directories and output paths.

## Publish a source export

```bash
python3 --version
python3 scripts/export-public.py
cd ../TermGPT-open-source
python3 scripts/audit-public.py
```

Exports include checked PNG sources; ICNS is generated at build time because system tools can add metadata. Exports exclude build output, logs, the original PRD, local validation notes, user settings, screenshots and Git history. Use a separate Git repository for the export and avoid `git add .` in a parent directory. Audits are not a professional secret scanner or security certification; review the final file list and diff.

For dual-architecture releases, commit first and run `./scripts/build-release.sh`. It checks Git, Python 3 and the build environment without reading accounts or runtime configuration.

## Scope and license

Not implemented: split terminals, combined multi-terminal context, an agent loop, exact command blocks, SFTP, MCP, SQLite, nested bookmark folders or native Anthropic/Gemini protocols.

MIT licensed. SwiftTerm upstream v1.9.0, commit `8840e3596739adfe9599c0e7fff89f4fa88bedcf`, retains its MIT license and copyright notices. Its local manifest is a macOS-only library with no remote dependencies; debug paths use the dynamic home directory. The AI-generated icon depicts a terminal prompt and sparkles without third-party trademarks. TermGPT is not an official OpenAI product.
