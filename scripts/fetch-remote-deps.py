#!/usr/bin/env python3
"""Fetch pinned upstream source archives into an ignored cache; verify SHA-256."""
import hashlib,json,sys,urllib.request,tarfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
if sys.version_info < (3,12): raise SystemExit('Python 3.12 or newer is required for safe archive extraction')
manifest=json.loads((root/'Vendor/RemoteDesktop/dependencies.json').read_text())
cache=root/'.build/remote-sources';cache.mkdir(parents=True,exist_ok=True)
for item in manifest:
 archive=cache/(item['name']+'.tar.gz')
 if not archive.exists():
  download=archive.with_suffix('.download')
  with urllib.request.urlopen(item['url'], timeout=60) as response, download.open('wb') as output:
   while chunk:=response.read(1024*1024):output.write(chunk)
  if hashlib.sha256(download.read_bytes()).hexdigest()!=item['sha256']: raise SystemExit('Dependency checksum mismatch: '+item['name'])
  download.replace(archive)
 digest=hashlib.sha256(archive.read_bytes()).hexdigest()
 if digest!=item['sha256']: raise SystemExit('Dependency checksum mismatch: '+item['name'])
 destination=cache/item['name']
 if not destination.exists():
  destination.mkdir()
  with tarfile.open(archive) as source:
   for member in source.getmembers():
    parts=Path(member.name).parts
    if len(parts)<2:continue
    member.name=str(Path(*parts[1:]));source.extract(member,destination,filter='data')
 print(item['name']+': verified')
