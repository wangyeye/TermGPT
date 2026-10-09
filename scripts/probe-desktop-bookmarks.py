#!/usr/bin/env python3
"""One live connection attempt per desktop bookmark, using saved local credentials.

Stops at the first frame or an RDP certificate challenge; never accepts certificates.
Only redacted protocol diagnostics are printed. No remote input or clipboard is sent.
"""
import argparse
import json
import os
import pathlib
import selectors
import subprocess
import sys
import time

if sys.version_info < (3, 9):
    raise SystemExit("Python 3.9 or newer is required")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("helper", type=pathlib.Path)
parser.add_argument("--minimal-environment", action="store_true", help="Reproduce the old app's restricted helper environment")
parser.add_argument("--app-environment", action="store_true", help="Use the corrected app helper environment")
args = parser.parse_args()
if not args.helper.is_file() or not os.access(args.helper, os.X_OK):
    raise SystemExit("Executable desktop helper required")
directory = pathlib.Path.home() / "Library/Application Support/TermGPT"
state = json.loads((directory / "workspace.json").read_text())
credentials = json.loads((directory / "credentials.json").read_text()).get("sshPasswords", {})
for bookmark in state.get("bookmarks", []):
    kind = bookmark.get("connectionKind", "ssh")
    if kind not in ("vnc", "rdp"):
        continue
    host = "".join(c for c in bookmark["host"] if ord(c) >= 32 and ord(c) != 127).strip()
    password = credentials.get(bookmark["id"], "")
    secrets = sorted(filter(None, [password, host, bookmark.get("user", ""), bookmark.get("domain", "")]), key=len, reverse=True)
    environment = {"PATH": "/usr/bin:/bin", "WLOG_LEVEL": "OFF"} if args.minimal_environment else None
    if args.app_environment:
        environment = dict(PATH="/usr/bin:/bin", WLOG_LEVEL="OFF", HOME=str(pathlib.Path.home()), TMPDIR=os.environ.get("TMPDIR", "/tmp"), LANG="en_US.UTF-8")
    process = subprocess.Popen([str(args.helper.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=environment)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    config = dict(protocol=kind, host=host, port=bookmark["port"], user=bookmark.get("user", ""), password=password, domain=bookmark.get("domain") or "", clipboard=False)
    print(json.dumps(dict(bookmark_id=bookmark["id"], protocol=kind, event="probe_start")), flush=True)
    try:
        process.stdin.write(json.dumps(config).encode() + b"\n"); process.stdin.flush()
        buffer = bytearray(); deadline = time.monotonic() + 30; done = False
        while not done and time.monotonic() < deadline:
            if not selector.select(timeout=0.5):
                continue
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                break
            buffer.extend(chunk)
            while len(buffer) >= 4:
                size = int.from_bytes(buffer[:4], "big")
                if not 1 <= size <= 40 * 1024 * 1024:
                    raise ValueError("invalid helper frame")
                if len(buffer) < size + 4:
                    break
                packet = bytes(buffer[4:4 + size]); del buffer[:4 + size]
                event = "frame_received" if packet[0] == 1 else "certificate_confirmation_needed" if packet[0] == 4 else "status"
                detail = packet[1:].decode("utf-8", errors="replace") if packet[0] in (2, 6) else ""
                if packet[0] == 1:
                    pixels = packet[9:]
                    detail = "nonblack_pixels=" + str(any(pixels[i] or pixels[i+1] or pixels[i+2] for i in range(0, len(pixels), 4)))
                for secret in secrets:
                    detail = detail.replace(secret, "[redacted]")
                print(json.dumps(dict(event=event, detail=detail[:4096])), flush=True)
                if packet[0] == 4 or (packet[0] == 1 and detail == "nonblack_pixels=True") or (packet[0] == 2 and ("failed" in detail or detail == "disconnected")):
                    done = True; break
        if not done:
            print(json.dumps(dict(event="ended_without_frame_or_certificate")), flush=True)
    finally:
        selector.close()
        try:
            process.stdin.write(b'{"type":"stop"}\n'); process.stdin.flush()
        except (OSError, BrokenPipeError):
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.terminate(); process.wait(timeout=5)
        try:
            process.stdin.close()
        except BrokenPipeError:
            pass
        process.stdout.close()
