#!/usr/bin/env python3
"""Read-only desktop transport probe; never reads credentials or authenticates."""
import argparse
import json
import pathlib
import socket
import struct
import sys

if sys.version_info < (3, 9):
    raise SystemExit("Python 3.9 or newer is required")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--workspace", type=pathlib.Path, default=pathlib.Path.home() / "Library/Application Support/TermGPT/workspace.json")
args = parser.parse_args()
if not args.workspace.is_file():
    raise SystemExit("Workspace configuration not found")
state = json.loads(args.workspace.read_text())

def read(sock, length):
    result = b""
    while len(result) < length:
        part = sock.recv(length - len(result))
        if not part:
            raise ConnectionError("server closed connection")
        result += part
    return result

for bookmark in state.get("bookmarks", []):
    kind = bookmark.get("connectionKind", "ssh")
    if kind not in ("vnc", "rdp"):
        continue
    result = {"protocol": kind, "bookmark_id": bookmark["id"], "port": bookmark["port"]}
    host = "".join(c for c in bookmark["host"] if ord(c) >= 32 and ord(c) != 127).strip()
    if host != bookmark["host"]:
        result["address_control_characters_removed"] = True
    try:
        with socket.create_connection((host, bookmark["port"]), timeout=5) as sock:
            sock.settimeout(5)
            result["tcp"] = "reachable"
            if kind == "vnc":
                banner = read(sock, 12)
                if not banner.startswith(b"RFB "):
                    raise ValueError("port is not a VNC RFB service")
                result["version"] = banner.decode("ascii").strip()
                version = b"RFB 003.008\n" if banner[4:11] >= b"003.008" else b"RFB 003.003\n"
                sock.sendall(version)
                if version == b"RFB 003.008\n":
                    count = read(sock, 1)[0]
                    result["security_types"] = list(read(sock, count)) if count else []
                else:
                    result["security_types"] = [struct.unpack(">I", read(sock, 4))[0]]
            else:
                sock.sendall(bytes.fromhex("030000130ee000000000000100080003000000"))
                header = read(sock, 4)
                payload = read(sock, int.from_bytes(header[2:4], "big") - 4)
                if len(payload) >= 8 and payload[-8] in (2, 3):
                    result["negotiation"] = "selected_protocol" if payload[-8] == 2 else "failure"
                    result["negotiation_value"] = int.from_bytes(payload[-4:], "little")
                else:
                    result["negotiation"] = "unexpected_response"
    except Exception as error:
        # Avoid returning OS exception strings containing a user's hostname.
        result["error"] = type(error).__name__
    print(json.dumps(result))
