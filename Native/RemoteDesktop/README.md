# Desktop bridge

The isolated helper links checksum-pinned FreeRDP and LibVNCClient. Build on macOS with Command Line Tools, CMake, Python 3, Perl and Make installed:

```sh
./scripts/build-remote-desktop.sh arm64 .build/remote-arm64 ON
python3 scripts/test-remote-desktop.py .build/remote-arm64/TermGPTRemoteDesktop --password --resize
python3 scripts/test-remote-desktop.py .build/remote-arm64/TermGPTRemoteDesktop --audio
python3 scripts/test-rdp-desktop.py .build/remote-arm64
```

Run these commands from the repository root. The build checks tools before use. Use `x86_64` for Intel. Tests use local synthetic services and never load personal credentials. Add `--initial-black --resize-black` to the VNC resize test to verify passive wake/refresh after each size change.

For bridge-only fixes after a full release build, `./scripts/repackage-desktop-fix.sh ORIGINAL_BUILD_COMMIT` rebuilds the native components for both architectures, signs the packages, audits them and regenerates source/checksums. It requires a clean Git tree and refuses reuse when Swift sources, assets, package metadata or vendor files differ from the original build commit. macOS and the same build tools are required; use the full release build for app changes.

`patch-libvnc.py` accepts valid RFB screen ID zero in the pinned upstream source. It is applied only to a disposable build snapshot and fails if the expected source changes. Invoke directly with `python3 Native/RemoteDesktop/patch-libvnc.py /path/to/libvnc/source` only on an unmodified build snapshot. The bridge preserves server screen identifiers when requesting a new size and falls back to local scaling when the server does not advertise resizing. RDP monitor requests wait for Display Control capabilities before sending.

`patch-freerdp.py` handles early desktop updates sent by older xrdp during authenticated resize reactivation. It discards these obsolete updates until synchronization completes, while initial authentication and normal update validation remain unchanged. Requires Python 3.8+; the build applies it to the disposable pinned FreeRDP snapshot. Direct usage: `python3 Native/RemoteDesktop/patch-freerdp.py /path/to/freerdp/source`. An unexpected upstream guard fails the build for review.

The RDP DesktopResize callback resets codec capacity together with the framebuffer, allowing four-pixel scanline padding used by xrdp. The authenticated live resize probe complements the loopback fixture; the fixture alone does not reproduce this xrdp behavior.

## Audio

RDP enables RDPSND with FreeRDP’s native macOS AudioQueue backend. Audio capture stays disabled; no microphone permission is requested. The server must provide audio redirection; xrdp needs its server audio modules. The loopback RDP fixture sends synthetic PCM and requires the playback acknowledgment alongside resize/input/clipboard checks.

VNC advertises QEMU Audio pseudo-encoding -259. Only a server announcing it receives format/enable requests. The requested format is signed 16-bit little-endian stereo PCM, 44100 Hz. Playback uses AudioQueue with a bounded one-second queue; excess audio is dropped to preserve desktop responsiveness. Invalid or oversized packets close the connection. Standard RFB Bell uses the system alert sound. Without the extension a VNC server cannot stream continuous audio. `--audio` verifies negotiation and AudioQueue consumption with a quiet synthetic tone; it does not read saved credentials. Both tests require macOS, Python 3, Command Line Tools and a built helper; RDP also checks OpenSSL availability.

Run audio tests with an available Mac output device. Playback queue/acknowledgment verifies the software path, not whether a person hears the speaker. Closing a session stops and disposes its audio queue.
