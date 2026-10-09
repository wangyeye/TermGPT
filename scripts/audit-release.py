#!/usr/bin/env python3
"""Read-only privacy checks of release ZIPs; requires Python 3, prints no content."""
import argparse
import re
import struct
import zipfile
from pathlib import Path
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archives', type=Path, nargs='+')
args = parser.parse_args()
allowed = {'TermGPT.app/Contents/Info.plist', 'TermGPT.app/Contents/MacOS/TermGPT', 'TermGPT.app/Contents/MacOS/TermGPTSSHAskpass',
           'TermGPT.app/Contents/MacOS/TermGPTRZ', 'TermGPT.app/Contents/MacOS/TermGPTSZ', 'TermGPT.app/Contents/Resources/lrzsz-COPYING.txt', 'TermGPT.app/Contents/Resources/TermGPT.icns', 'TermGPT.app/Contents/_CodeSignature/CodeResources'}
allowed.add('TermGPT.app/Contents/MacOS/TermGPTRemoteDesktop')
allowed.update('TermGPT.app/Contents/Resources/RemoteDesktop-' + name + '.txt' for name in
               ['NOTICE', 'FreeRDP-LICENSE', 'LibVNC-COPYING', 'OpenSSL-LICENSE', 'GPL-3.0'])
for archive in args.archives:
    if not archive.is_file():
        raise SystemExit('Release archive not found.')
    with zipfile.ZipFile(archive) as bundle:
        for item in bundle.infolist():
            if item.is_dir():
                continue
            if item.filename not in allowed:
                raise SystemExit('Unexpected release file; do not upload.')
            data = bundle.read(item)
            for pattern in [rb'/Users/[A-Za-z0-9_.-]+/', rb'\b[A-Za-z0-9._%+-]+@qq\.com\b', rb'gh[pousr]_[A-Za-z0-9]{30,}', rb'github_pat_[A-Za-z0-9_]{30,}', rb'sk-(?:proj-)?[A-Za-z0-9_-]{30,}']:
                if re.search(pattern, data):
                    raise SystemExit('Personal path or credential-like value found; do not upload.')
            if item.filename.endswith('.icns'):
                pos = 8
                while pos + 8 <= len(data):
                    size = struct.unpack('>I', data[pos+4:pos+8])[0]
                    if size < 8 or pos + size > len(data):
                        raise SystemExit('Invalid icon container.')
                    png = data[pos+8:pos+size]; pos += size
                    if not png.startswith(b'\x89PNG\r\n\x1a\n'):
                        continue
                    offset = 8
                    while offset + 12 <= len(png):
                        count = struct.unpack('>I', png[offset:offset+4])[0]
                        tag = png[offset+4:offset+8]
                        chunk = png[offset+8:offset+8+count]
                        offset += count + 12
                        if tag in {b'tEXt', b'zTXt', b'iTXt'}:
                            raise SystemExit('Icon contains text metadata.')
                        if tag == b'eXIf':
                            endian = '<' if chunk[:2] == b'II' else '>'
                            seen = set()
                            def inspect(directory):
                                if directory in seen or directory + 2 > len(chunk):
                                    raise SystemExit('Invalid EXIF directory.')
                                seen.add(directory)
                                entries = struct.unpack(endian+'H', chunk[directory:directory+2])[0]
                                for n in range(entries):
                                    start = directory + 2 + 12*n
                                    if start + 12 > len(chunk):
                                        raise SystemExit('Invalid EXIF entry.')
                                    code, kind, count, value = struct.unpack(endian+'HHII', chunk[start:start+12])
                                    if code == 0x8769 and kind == 4 and count == 1:
                                        inspect(value)
                                    elif code in {0x0112, 0x011a, 0x011b, 0x0128, 0xa001, 0xa002, 0xa003} and kind in {3, 4, 5} and count == 1:
                                        pass  # Numeric orientation/resolution/color-space/pixel dimensions only.
                                    else:
                                        raise SystemExit('Icon contains EXIF outside the numeric display allowlist.')
                                following = directory + 2 + 12*entries
                                if following + 4 <= len(chunk):
                                    next_directory = struct.unpack(endian+'I', chunk[following:following+4])[0]
                                    if next_directory:
                                        inspect(next_directory)
                            inspect(struct.unpack(endian+'I', chunk[4:8])[0])
    print(archive.name + ': package file allowlist and privacy checks passed')
