#!/usr/bin/env python3
"""Create corresponding source distribution using only pinned upstream archives and explicit project files."""
import hashlib, json, subprocess, sys, tarfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
if not (root/'Vendor/RemoteDesktop/dependencies.json').is_file():raise SystemExit('Missing dependency manifest')
subprocess.run([sys.executable,str(root/'scripts/fetch-remote-deps.py')],check=True)
paths=[Path('Native/RemoteDesktop'),Path('Vendor/RemoteDesktop'),Path('scripts/build-remote-desktop.sh'),Path('scripts/fetch-remote-deps.py')]
manifest=json.loads((root/'Vendor/RemoteDesktop/dependencies.json').read_text())
output=root/'dist/TermGPT-RemoteDesktop-source.tar.gz';output.parent.mkdir(exist_ok=True)
with tarfile.open(output,'w:gz') as bundle:
    def clean(info):info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0;return info
    for relative in paths:bundle.add(root/relative,arcname=str(Path('TermGPT-RemoteDesktop-source')/relative),filter=clean)
    for item in manifest:
        archive=root/'.build/remote-sources'/(item['name']+'.tar.gz')
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=item['sha256']:raise SystemExit('Source archive checksum mismatch')
        bundle.add(archive,arcname='TermGPT-RemoteDesktop-source/upstream/'+archive.name,filter=clean)
print(output.name+': verified upstream source and explicit bridge/build files only')
