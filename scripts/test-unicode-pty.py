#!/usr/bin/env python3
"""Reproduce zsh's C-locale Unicode display problem and verify a UTF-8 PTY."""
import errno
import os
import platform
import select
import shutil
import signal
import sys
import tempfile
import time

TEXT = '# 添加 Python 3.14 PATH 配置'

def collect(fd, until, timeout=5):
    data = b''
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not select.select([fd], [], [], 0.1)[0]:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not chunk:
            break
        data += chunk
        if until in data:
            break
    return data

def trial(unicode_locale):
    with tempfile.TemporaryDirectory(prefix='termgpt-unicode-') as home:
        env = {'PATH': '/usr/bin:/bin', 'TERM': 'xterm-256color', 'HOME': home}
        if unicode_locale:
            env.update(LANG='en_US.UTF-8', LC_CTYPE='en_US.UTF-8', LC_MESSAGES='C')
        else:
            env.update(LANG='C', LC_ALL='C')
        pid, fd = os.forkpty()
        if pid == 0:
            os.execve('/bin/zsh', ['zsh', '-f', '-i', '-c', "printf '\\nPTY_READY\\n'; vared -c -p 'input> ' line; printf '\\nPAYLOAD:%s\\n' \"$line\""], env)
        try:
            ready = collect(fd, b'input> ')
            if b'input> ' not in ready:
                raise RuntimeError('zsh did not become ready')
            os.write(fd, TEXT.encode())
            display = collect(fd, TEXT.encode(), timeout=1)
            os.write(fd, b'\r')
            result = collect(fd, b'PAYLOAD:' + TEXT.encode(), timeout=5)
            if unicode_locale:
                assert TEXT.encode() in display, 'UTF-8 input display failed'
                assert b'PAYLOAD:' + TEXT.encode() in result, 'Shell received altered UTF-8 bytes'
                print('UTF-8 locale: Chinese input display and received payload passed')
            else:
                assert TEXT.encode() not in display, 'Control did not reproduce the C-locale issue'
                print('C locale: reproduced escaped/garbled Chinese input display')
        finally:
            os.close(fd)
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)

if __name__ == '__main__':
    if sys.version_info < (3, 8) or platform.system() != 'Darwin' or not shutil.which('zsh'):
        sys.exit('Requires macOS, Python 3.8+ and /bin/zsh.')
    trial(False)
    trial(True)
