#!/usr/bin/env python3
"""Read-only checks of a source export or exact Git-tracked content; prints no secrets."""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
parser.add_argument('--tracked', action='store_true', help='Inspect only Git-tracked files')
parser.add_argument('--report', type=Path, help='Optional local JSON report without file contents')
args = parser.parse_args()
root = args.root.resolve()
if not (root / 'Package.swift').is_file():
    raise SystemExit('Expected a TermGPT project root.')
if args.tracked:
    if not shutil.which('git'):
        raise SystemExit('Git is required for --tracked.')
    listing = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z'])
    files = [root / rel.decode() for rel in listing.split(b'\0') if rel]
else:
    files = sorted(p for p in root.rglob('*') if p.is_file() and '.git' not in p.relative_to(root).parts)
if not files:
    raise SystemExit('No files to audit; refusing an empty result.')
checks = {
    'personal-home-path': re.compile(r'/Users/[A-Za-z0-9_.-]+/'),
    'email-in-first-party-code': re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
    'private-network-address': re.compile(r'\b(?:192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)\b'),
    'credential-like-token': re.compile(r'\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})\b'),
    'private-key-material': re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----\s+[A-Za-z0-9+/=]{64,}'),
}
forbidden_parts = {'.build', 'dist', '.swiftpm', '__pycache__', '.DS_Store', 'xcuserdata'}
forbidden_names = {'PRD.md', 'VALIDATION.md', 'workspace.json', '.env'}
issues = []
manifest = []
for path in files:
    rel = path.relative_to(root)
    if path.is_symlink() or any(p in forbidden_parts for p in rel.parts) or path.name in forbidden_names or path.name.startswith('.env.') or path.suffix in {'.log', '.pem', '.key', '.p12', '.pfx', '.pyc'}:
        issues.append({'file': str(rel), 'check': 'excluded-file'})
        continue
    data = path.read_bytes()
    manifest.append({'file': str(rel), 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    if path.suffix in {'.png', '.icns'}:
        if rel not in [Path('Assets/AppIcon.png'), Path('Assets/TermGPT.icns')]:
            issues.append({'file': str(rel), 'check': 'unexpected-binary'})
        # Parse real chunks rather than searching compressed pixels for byte strings.
        images = [data] if path.suffix == '.png' else []
        if path.suffix == '.icns':
            offset = 8
            while offset + 8 <= len(data):
                size = struct.unpack('>I', data[offset + 4:offset + 8])[0]
                if size < 8 or offset + size > len(data):
                    issues.append({'file': str(rel), 'check': 'invalid-icon-container'})
                    break
                payload = data[offset + 8:offset + size]
                if payload.startswith(b'\x89PNG\r\n\x1a\n'):
                    images.append(payload)
                offset += size
        for png in images:
            offset = 8
            while offset + 12 <= len(png):
                size = struct.unpack('>I', png[offset:offset + 4])[0]
                tag = png[offset + 4:offset + 8]
                if tag in {b'tEXt', b'zTXt', b'iTXt', b'eXIf'}:
                    issues.append({'file': str(rel), 'check': 'image-text-metadata'})
                offset += size + 12
        continue
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        issues.append({'file': str(rel), 'check': 'unexpected-binary'})
        continue
    for name, pattern in checks.items():
        if name == 'email-in-first-party-code' and rel.parts[0] == 'Vendor':
            continue  # Upstream public attribution remains under its original license.
        for match in pattern.finditer(text):
            issues.append({'file': str(rel), 'line': text.count('\n', 0, match.start()) + 1, 'check': name})
report = {'files': len(manifest), 'issues': issues, 'manifest': manifest}
if args.report:
    args.report.write_text(json.dumps(report, indent=2) + '\n')
print('Audited files:', len(manifest), '| Findings:', len(issues))
for issue in issues:
    print(json.dumps(issue))
if issues:
    raise SystemExit(1)
