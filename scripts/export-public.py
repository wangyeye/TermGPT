#!/usr/bin/env python3
"""Create a fresh, allowlisted source-only directory; never copy runtime data/history."""
import argparse
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT.parent / 'TermGPT-open-source')
args = parser.parse_args()
if not shutil.which('git') or not (ROOT / 'Package.swift').is_file():
    raise SystemExit('Requires Git and the complete TermGPT source directory.')
out = args.output.resolve()
if out.exists():
    raise SystemExit('Output already exists; choose a fresh directory with --output. Nothing overwritten.')
if out == ROOT or ROOT in out.parents:
    raise SystemExit('Output must be outside the input source directory.')
roots = ['README.md', 'LICENSE', 'SECURITY.md', 'PUBLISHING.md', '.gitignore', 'Package.swift', 'Sources', 'Tests',
         'Assets', 'scripts', 'Vendor/SwiftTerm/Package.swift',
         'Vendor/SwiftTerm/LICENSE', 'Vendor/SwiftTerm/Sources/SwiftTerm']
files = []
for name in roots:
    src = ROOT / name
    if not src.exists():
        raise SystemExit('Missing source: ' + name)
    for item in ([src] if src.is_file() else sorted(src.rglob('*'))):
        if item.is_symlink():
            raise SystemExit('Symlink is not allowed in public export.')
        if not item.is_file():
            continue
        rel = item.relative_to(ROOT)
        if any(part in {'.git', '.build', '.swiftpm', '__pycache__', '.DS_Store'} for part in rel.parts):
            continue
        if item.suffix in {'.log', '.pyc', '.icns'}:
            continue
        files.append(rel)
out.mkdir(parents=True)
for rel in files:
    target = out / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes((ROOT / rel).read_bytes())
    target.chmod(0o755 if rel.parts[0] == 'scripts' and target.suffix in {'.py', '.sh'} else 0o644)
subprocess.run(['python3', str(out / 'scripts/audit-public.py'), '--root', str(out)], check=True)
print('Source-only export ready; files:', len(files))
print('No credentials, runtime state, build output or Git history are copied.')
