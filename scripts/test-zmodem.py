#!/usr/bin/env python3
"""Real two-way ZMODEM helper verification using temporary synthetic files."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import threading

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('helper_directory', type=Path)
args = parser.parse_args()
sender = args.helper_directory.resolve() / 'TermGPTSZ'
receiver = args.helper_directory.resolve() / 'TermGPTRZ'
for program in (sender, receiver):
    if not os.access(program, os.X_OK):
        raise SystemExit('Build executable helpers first with scripts/build-zmodem.sh.')
with tempfile.TemporaryDirectory(prefix='termgpt-zmodem-test-') as temporary:
    root = Path(temporary)
    source = root / 'source'; destination = root / 'destination'
    source.mkdir(); destination.mkdir()
    payload = bytes(range(256)) * 4096
    files = {'中文 space.bin': payload, 'empty.txt': b''}
    for name, data in files.items():
        (source / name).write_bytes(data)
    for round_number in range(2):
        send_read, recv_write = os.pipe()
        recv_read, send_write = os.pipe()
        recv = subprocess.Popen([str(receiver), '--restricted', '--rename', '--binary', '--syslog=off'], stdin=recv_read, stdout=recv_write, stderr=subprocess.PIPE, cwd=destination)
        send = subprocess.Popen([str(sender), '--binary', '--escape', '--syslog=off', '--', *map(str, source.iterdir())], stdin=send_read, stdout=send_write, stderr=subprocess.PIPE)
        for fd in (send_read, recv_write, recv_read, send_write): os.close(fd)
        diagnostic = []
        readers = [threading.Thread(target=lambda p=p: diagnostic.append(p.stderr.read())) for p in (send, recv)]
        for reader in readers: reader.start()
        try:
            send.wait(timeout=30); recv.wait(timeout=30)
        except subprocess.TimeoutExpired:
            send.kill(); recv.kill(); raise SystemExit('ZMODEM test timed out')
        finally:
            for reader in readers: reader.join(timeout=3)
        if round_number == 0 and (send.returncode or recv.returncode):
            raise SystemExit('ZMODEM round trip failed: ' + b'\n'.join(diagnostic).decode(errors='replace'))
        if round_number == 1 and recv.returncode == 0:
            raise SystemExit('Restricted receiver unexpectedly replaced existing files')
        expected = set(files.values())
        received = [p.read_bytes() for p in destination.iterdir()]
        if len(received) != len(files) or any(data not in expected for data in received):
            raise SystemExit('ZMODEM payload or non-overwrite check failed')
print('ZMODEM round trips passed: binary, UTF-8/spaces, empty files, multi-file and non-overwrite.')
