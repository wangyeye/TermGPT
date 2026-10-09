# Development and scripts

[简体中文](DEVELOPMENT.zh-CN.md) · [Main README](../README.md)

Run scripts from the repository root. All processing scripts are kept in `scripts/`. Check the environment before use:

```bash
./scripts/check-environment.sh
python3 --version
cmake --version
```

macOS 13+, Swift 5.9+, Command Line Tools and system SSH/zsh are required. Native desktop builds require CMake 3.20+, Python 3.12+, make and Perl; dependencies are downloaded and checksum-verified into ignored `.build` caches. XCTest needs full Xcode at `/Applications/Xcode.app`. Scripts do not accept Xcode licenses or replace the default toolchain. Python fixtures require 3.8+, desktop diagnostics 3.9+. See each script's usage/help and dependency checks.

## Common workflows

```bash
./scripts/build.sh
./scripts/run.sh
./scripts/test-with-fixture.sh
./scripts/verify-package.sh
```

Build output is `dist/TermGPT.app` and an architecture-specific ZIP. The API fixture uses loopback and synthetic data. Tests cover credentials/file permissions, PTY input, selection scrolling, bookmark order, context, OAuth and UI preferences. Package verification independently checks extraction, plist, architecture and signatures; it does not establish notarization or remote-server compatibility.

For source timestamp problems in synced directories, use `./scripts/test-isolated.sh`. After updating the app, reconnect SSH tabs to apply UTF-8 environment changes. A remote shell may override or reject forwarded locale settings.

## Release

Update the version/build in `scripts/package-app.sh`, commit a clean tree, then:

```bash
./scripts/build-release.sh
python3 scripts/audit-public.py --tracked
python3 scripts/audit-release.py dist/TermGPT-macOS-arm64.zip dist/TermGPT-macOS-x86_64.zip
```

The release builder snapshots committed source under `/private/tmp`, builds both architectures, signs and audits packages, bundles corresponding desktop source and writes `dist/SHA256SUMS`. Review the file list/diff, upload the two ZIPs, source archive and checksums to a draft GitHub Release, verify uploaded hashes and only then publish. Never upload runtime configuration, credentials, logs or screenshots. Audits are limited checks, not a security certification.

To install locally, quit the app, then run `./scripts/install-local-release.sh /absolute/path/to/TermGPT-macOS-arm64.zip` (Intel uses its own ZIP). It checks environment, architecture and signature, replaces `/Applications/TermGPT.app` and retains user configuration. Restart disconnects active sessions.

## Browser fixture

```bash
python3 scripts/webview-fixture.py
```

Create a temporary WEB bookmark for the printed loopback URL. Test navigation, spell correction, duplicate-tab choices and Basic Auth at `/auth` using the synthetic username/password `fixture` / `fixture`. Stop with Ctrl+C and delete the temporary bookmark. If you tested saved authentication, run:

```bash
python3 scripts/webview-fixture.py --clear-saved-auth "$HOME/Library/Application Support/TermGPT/credentials.json"
```

Cleanup removes only that exact loopback fixture credential and does not print other entries.

The same page also includes a username/password form and a noVNC-style prompt. Use `fixture` / `fixture`, accept Save and Autofill, then reopen the bookmark to verify prefilled fields. Declining must leave credentials unsaved; autofill must not submit the form. Cleanup above also removes these exact synthetic entries.

## Script reference

### RDP connection probe

Requires Python 3.8+ and network access to the requested host. Run `python3 scripts/probe-rdp.py HOST --port 3389` to check TCP and the initial RDP security negotiation. No credentials are sent. To compare the installed native engine, add `--helper /Applications/TermGPT.app/Contents/MacOS/TermGPTRemoteDesktop`; it uses empty credentials, stops at certificate verification without accepting it, and never opens a desktop. Diagnostic output can contain the requested host and public certificate details; keep it local. A successful probe does not verify account authentication. If the probe works but the app immediately fails, check macOS Privacy & Security → Local Network permission for TermGPT and retry the app connection.
For an authenticated resize check, explicitly add `--saved-bookmark BOOKMARK_UUID --resize 1466 873 --resize-after-frame`. This reads only that matching local RDP bookmark and its saved password, and accepts only its previously trusted certificate fingerprint. It connects for 20 seconds and reports frame dimensions without saving pixels or sending keyboard input. `--clipboard-channel` negotiates clipboard support without sending clipboard contents. `--safe-debug` prints filtered core errors; keep diagnostic output private.


| Script in `scripts/` | Purpose and usage |
| --- | --- |
| `check-environment.sh` | Check macOS, toolchain, SSH/zsh and vendored terminal dependency |
| `build.sh`, `run.sh` | Build/package the current architecture; launch (build first if missing) |
| `package-app.sh` | Assemble/sign/ZIP release binaries; optional binary path argument |
| `build-release.sh` | Full ARM/Intel build from a clean Git commit and privacy/package checks |
| `verify-package.sh` | Independently check a ZIP; optional ZIP and expected architecture arguments |
| `install-local-release.sh` | Verify/install a ZIP locally; requires Applications write permission |
| `toolchain.sh` | Sourced by build/test scripts to select caches, plugins and XCTest paths |
| `make-icon.sh` | Check sips/iconutil, generate ICNS from checked PNG assets |
| `test.sh`, `test-with-fixture.sh` | XCTest; optionally start and clean a synthetic loopback AI provider |
| `test-isolated.sh` | Snapshot source outside synced folders before running tests |
| `mock-provider.py` | Fixed SSE provider fixture; stop with Ctrl+C |
| `webview-fixture.py` | Browser/Basic Auth fixture and exact synthetic credential cleanup |
| `probe-rdp.py` | TCP/RDP negotiation and optional native-engine probe without credentials; see above |
| `test-unicode-pty.py` | Compare C/UTF-8 zsh PTY display and payload in a temporary HOME |
| `build-zmodem.sh` | Build rz/sz helpers for `arm64` or `x86_64` |
| `test-zmodem.py` | Test binary, Unicode, empty and multi-file transfers with synthetic files; pass helper directory |
| `fetch-remote-deps.py` | Fetch pinned, checksum-verified desktop dependency sources |
| `build-remote-desktop.sh` | Build native desktop helper; architecture, output directory and optional test-server flag |
| `test-remote-desktop.py`, `test-rdp-desktop.py` | Synthetic loopback protocol tests; no real saved credentials |
| `diagnose-desktop.py` | Read bookmark addresses, check reachability/negotiation; no password reads or login |
| `probe-desktop-bookmarks.py` | Explicit live diagnostic with saved credentials; pass helper path and `--app-environment`; no clicks/keys/clipboard, may move VNC pointer to wake display |
| `package-remote-source.py` | Verify and package corresponding upstream/helper/build source |
| `audit-public.py`, `audit-release.py` | Source/package allowlists, private-path/credential patterns and metadata checks |
| `export-public.py` | Create an allowlisted source export; excludes runtime data/build output/history |
| `rebuild-swift-release.sh` | Rebuild Swift using verified local packages; pass their original build commit. Allows version/build-number updates only; refuses native, asset or other packaging changes. Never overwrite published release assets. |
| `repack-desktop.sh`, `repackage-desktop-fix.sh` | Historical desktop-only repair workflows with script-specific version/input checks; use full release build for new releases |
| `update-provider-ui.py`, `migrate-bilingual-ui.py` | Historical one-time migrations; not required for normal builds |

## Source and dependencies

- `Sources/TermGPT`: app UI, terminal, web/desktop sessions, AI, localization and JSON storage.
- `Sources/TermGPTSSHAskpass`: OpenSSH password and host-verification helper.
- `Tests/TermGPTTests`: synthetic unit/local integration tests.
- `Assets`: icon sources and generation instructions.
- `Vendor/SwiftTerm`: pinned terminal library and local patch notes.
- `Vendor/lrzsz`, `Vendor/RemoteDesktop`, `Native`: isolated transfer/desktop engines, notices and build definitions.

See [desktop engine notes](../Vendor/RemoteDesktop/README.md) for protocol constraints, dependency licenses and fixture instructions. Diagnostics involving saved hosts are distinct from synthetic tests; running automated checks does not verify every account, remote server or physical Intel Mac.

Use `/legacy` to verify old-style `input type="button"` login controls with spaced Chinese labels and hidden password-change fields. Saving and reopening must fill only the visible login pair without clicking the button.
