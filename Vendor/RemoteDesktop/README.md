# Embedded desktop engines

TermGPT runs the VNC/RDP client in a separate `TermGPTRemoteDesktop` process. The main application exchanges framed RGBA images and input messages through private pipes; credentials never appear in process arguments. The helper is GPL-3.0-or-later; the main app remains under its own license.

`dependencies.json` pins official upstream source archives and SHA-256 hashes:

- FreeRDP 3.32.1 — Apache-2.0, RDP client, TLS/NLA and CLIPRDR text clipboard.
- LibVNCServer / LibVNCClient 0.9.15 — GPL-2.0-or-later, RFB/VNC client.
- OpenSSL 3.6.5 — Apache-2.0, statically linked crypto and built-in legacy algorithms needed for VNC authentication and NTLM.

Sources are fetched into the ignored `.build/remote-sources` cache and verified before extraction. No global library installation is required. Builds require macOS 13+, Command Line Tools, CMake 3.20+, Python 3.12+, make and Perl; the build script checks available tools before use. Apple Silicon can cross-build the Intel helper.

```sh
./scripts/build-remote-desktop.sh arm64
./scripts/build-remote-desktop.sh x86_64
# Optional synthetic TLS RDP server, for tests only:
./scripts/build-remote-desktop.sh arm64 .build/remote-arm64 ON
python3 scripts/test-remote-desktop.py
python3 scripts/test-rdp-desktop.py
```

Tests bind only loopback and use temporary synthetic data. They never read saved passwords. RDP fixture tests TLS; it does not establish Windows account/NLA compatibility. The test server is excluded from release packages.

Release source archives include these unmodified upstream archives, the helper sources, dependency manifest and build scripts. License notices are included in the app bundle. VNC traditional authentication does not encrypt the desktop session. UTF-8 clipboard requires the server's extended clipboard support; traditional servers support Latin-1 text only. Clipboard sharing is text-only (up to 1 MiB), restricted to the selected desktop tab. Audio, drive redirection, file clipboard, multi-monitor and RDP gateways are not enabled.
