#!/usr/bin/env python3
"""Check TCP and RDP negotiation without credentials or desktop login."""
import argparse
import socket
import struct
import sys
import json
import os
import selectors
import subprocess
import time
from pathlib import Path

if sys.version_info < (3, 8):
    raise SystemExit('Python 3.8+ required')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('host')
parser.add_argument('--port', type=int, default=3389)
parser.add_argument('--helper', help='Optional TermGPTRemoteDesktop executable; tests until certificate, without credentials')
args = parser.parse_args()
if args.helper:
    helper = Path(args.helper)
    if not helper.is_file() or not os.access(helper, os.X_OK):
        raise SystemExit('Helper executable unavailable')
    process = subprocess.Popen([str(helper)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    config = dict(protocol='rdp', host=args.host, port=args.port, user='', password='', domain='', clipboard=False,
                  width=720, height=600, diagnostic=True)
    process.stdin.write((json.dumps(config) + '\n').encode()); process.stdin.flush()
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    selector.register(process.stderr, selectors.EVENT_READ)
    buffer = b''
    deadline = time.monotonic() + 20
    try:
        while time.monotonic() < deadline:
            for key, _ in selector.select(1):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                if key.fileobj is process.stderr:
                    # No credentials were supplied; protocol diagnostics only.
                    print(data.decode(errors='replace'), end='')
                    continue
                buffer += data
                while len(buffer) >= 4:
                    length = struct.unpack('>I', buffer[:4])[0]
                    if length > 40 * 1024 * 1024:
                        raise SystemExit('Invalid helper packet')
                    if len(buffer) < 4 + length:
                        break
                    kind, payload = buffer[4], buffer[5:4 + length]
                    buffer = buffer[4 + length:]
                    if kind == 4:
                        print('Helper reached certificate verification; stopped without trusting or logging in')
                        raise SystemExit(0)
                    if kind in (2, 6):
                        print(payload.decode(errors='replace'))
            if not selector.get_map():
                raise SystemExit(process.wait())
        raise SystemExit('Helper probe timed out')
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()
        selector.close()
try:
    with socket.create_connection((args.host, args.port), timeout=5) as conn:
        conn.settimeout(5)
        print('TCP connection established')
        # X.224 Connection Request, RDP_NEG_REQ: TLS or NLA.
        conn.sendall(bytes.fromhex('030000130ee000000000000100080003000000'))
        data = b''
        while len(data) < 4:
            part = conn.recv(4 - len(data))
            if not part:
                raise ValueError('Server closed before RDP response')
            data += part
        length = struct.unpack('>H', data[2:4])[0]
        if data[:2] != b'\x03\x00' or not 11 <= length <= 4096:
            raise ValueError('Not a valid RDP TPKT response')
        while len(data) < length:
            part = conn.recv(length - len(data))
            if not part:
                raise ValueError('Incomplete RDP response')
            data += part
        if len(data) >= 19 and data[11] in (2, 3):
            value = struct.unpack('<I', data[15:19])[0]
            if data[11] == 3:
                raise ValueError('RDP negotiation rejected: code %d' % value)
            print('RDP negotiation accepted: ' + {0: 'RDP', 1: 'TLS', 2: 'NLA', 8: 'NLA Extended'}.get(value, str(value)))
        else:
            print('X.224 response received; no security negotiation result')
except (OSError, ValueError) as error:
    raise SystemExit(str(error))
