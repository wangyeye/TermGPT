#!/usr/bin/env python3
"""Accept valid RFB screen ID zero in the pinned LibVNCClient source snapshot."""
import sys
from pathlib import Path
if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 patch-libvnc.py /path/to/libvnc/source')
path = Path(sys.argv[1]) / 'src/libvncclient/rfbclient.c'
source = path.read_text()
old = 'if (screen.id != 0 && screen.width && screen.height) {'
new = 'if (screen.width && screen.height) {'
if source.count(old) != 1:
    raise SystemExit('Pinned LibVNCClient screen layout source changed; review required')
path.write_text(source.replace(old, new))
