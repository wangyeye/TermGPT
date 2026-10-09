# Desktop bridge

The isolated helper links checksum-pinned FreeRDP and LibVNCClient. Build on macOS with Command Line Tools, CMake, Python 3, Perl and Make installed:

```sh
./scripts/build-remote-desktop.sh arm64 .build/remote-arm64 ON
python3 scripts/test-remote-desktop.py .build/remote-arm64/TermGPTRemoteDesktop --password --resize
python3 scripts/test-rdp-desktop.py .build/remote-arm64
```

Run these commands from the repository root. The build checks tools before use. Use `x86_64` for Intel. Tests use local synthetic services and never load personal credentials. Add `--initial-black --resize-black` to the VNC resize test to verify passive wake/refresh after each size change.

For bridge-only fixes after a full release build, `./scripts/repackage-desktop-fix.sh ORIGINAL_BUILD_COMMIT` rebuilds the native components for both architectures, signs the packages, audits them and regenerates source/checksums. It requires a clean Git tree and refuses reuse when Swift sources, assets, package metadata or vendor files differ from the original build commit. macOS and the same build tools are required; use the full release build for app changes.

`patch-libvnc.py` accepts valid RFB screen ID zero in the pinned upstream source. It is applied only to a disposable build snapshot and fails if the expected source changes. Invoke directly with `python3 Native/RemoteDesktop/patch-libvnc.py /path/to/libvnc/source` only on an unmodified build snapshot. The bridge preserves server screen identifiers when requesting a new size and falls back to local scaling when the server does not advertise resizing. RDP monitor requests wait for Display Control capabilities before sending.
