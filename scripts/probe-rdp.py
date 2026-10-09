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
parser.add_argument('--user', default='', help='Optional account name for negotiation; no password is sent')
parser.add_argument('--saved-bookmark', help='Explicitly test this local bookmark using its saved login and previously trusted certificate')
parser.add_argument('--resize', type=int, nargs=2, metavar=('WIDTH', 'HEIGHT'), help='Test an early display resize after connecting')
parser.add_argument('--clipboard-channel', action='store_true', help='Negotiate clipboard support without sending clipboard contents')
parser.add_argument('--resize-after-frame', action='store_true', help='Wait for initial pixels before the resize test')
parser.add_argument('--safe-debug', action='store_true', help='Show only core protocol errors, omitting authentication diagnostics')
args = parser.parse_args()
if args.saved_bookmark and not args.helper:
    raise SystemExit('--saved-bookmark requires --helper')
if args.helper:
    helper = Path(args.helper)
    if not helper.is_file() or not os.access(helper, os.X_OK):
        raise SystemExit('Helper executable unavailable')
    config = dict(protocol='rdp', host=args.host, port=args.port, user=args.user, password='', domain='', clipboard=args.clipboard_channel,
                  width=720, height=600, diagnostic=True)
    pin = None
    if args.saved_bookmark:
        directory = Path.home() / 'Library/Application Support/TermGPT'
        state = json.loads((directory / 'workspace.json').read_text())
        bookmark = next((b for b in state['bookmarks'] if b['id'] == args.saved_bookmark), None)
        if not bookmark or bookmark.get('connectionKind') != 'rdp' or bookmark['host'] != args.host or bookmark['port'] != args.port:
            raise SystemExit('Bookmark does not match requested RDP target')
        vault = json.loads((directory / 'credentials.json').read_text())
        pin = vault.get('rdpCertificates', {}).get(args.saved_bookmark)
        password = vault.get('sshPasswords', {}).get(args.saved_bookmark)
        if not password or not pin or pin['host'] != args.host.lower() or pin['port'] != args.port:
            raise SystemExit('Saved password and exact prior certificate trust required')
        config.update(user=bookmark['user'], password=password, domain=bookmark.get('domain', ''), diagnostic=args.safe_debug)
    process = subprocess.Popen([str(helper)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    process.stdin.write((json.dumps(config) + '\n').encode()); process.stdin.flush()
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    selector.register(process.stderr, selectors.EVENT_READ)
    buffer = b''
    deadline = time.monotonic() + 20
    frame_seen = False
    last_size = None
    try:
        while time.monotonic() < deadline:
            for key, _ in selector.select(1):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                if key.fileobj is process.stderr:
                    # Saved-login probes suppress authentication diagnostics.
                    if not args.saved_bookmark:
                        print(data.decode(errors='replace'), end='')
                    elif args.safe_debug:
                        for line in data.decode(errors='replace').splitlines():
                            if '[ERROR]' in line and any(tag in line for tag in ('[com.freerdp.core', '[com.freerdp.gdi', '[com.freerdp.codec')) and not any(word in line.lower() for word in ('nla', 'credssp', 'ntlm', 'password')):
                                print(line.replace(config['password'], '[redacted]'))
                    continue
                buffer += data
                while len(buffer) >= 4:
                    length = struct.unpack('>I', buffer[:4])[0]
                    if not 1 <= length <= 40 * 1024 * 1024:
                        raise SystemExit('Invalid helper packet')
                    if len(buffer) < 4 + length:
                        break
                    kind, payload = buffer[4], buffer[5:4 + length]
                    buffer = buffer[4 + length:]
                    if kind == 4:
                        if args.saved_bookmark:
                            certificate = json.loads(payload)
                            if certificate['host'].lower() != pin['host'] or certificate['fingerprint'].replace(':', '').lower() != pin['fingerprint']:
                                raise SystemExit('Certificate differs from previously trusted pin; no login attempted')
                            process.stdin.write(b'{"type":"certificate","accept":true}\n'); process.stdin.flush()
                            print('Previously trusted certificate matched')
                            continue
                        print('Helper reached certificate verification; stopped without trusting or logging in')
                        raise SystemExit(0)
                    if kind == 1 and args.saved_bookmark:
                        width, height = struct.unpack('>II', payload[:8])
                        if (width, height) != last_size:
                            print('Authenticated desktop frame received: %dx%d; no pixels saved' % (width, height))
                            last_size = (width, height)
                        if not args.resize:
                            raise SystemExit(0)
                        if args.resize_after_frame and not frame_seen:
                            process.stdin.write((json.dumps(dict(type='resize', width=args.resize[0], height=args.resize[1])) + '\n').encode()); process.stdin.flush()
                        frame_seen = True
                    if kind in (2, 6):
                        message = payload.decode(errors='replace')
                        if args.saved_bookmark:
                            message = message.replace(config['password'], '[redacted]')
                        print(message)
                        if kind == 2 and message == 'connected' and args.resize and not args.resize_after_frame:
                            process.stdin.write((json.dumps(dict(type='resize', width=args.resize[0], height=args.resize[1])) + '\n').encode()); process.stdin.flush()
                        if kind == 2 and message == 'disconnected':
                            raise SystemExit('Disconnected during probe')
            if not selector.get_map():
                raise SystemExit(process.wait())
        if frame_seen:
            print('Desktop remained connected during resize probe')
            raise SystemExit(0)
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
