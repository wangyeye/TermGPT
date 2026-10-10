#!/usr/bin/env python3
"""Print counts and a layout fingerprint without exposing bookmarks or credentials."""
import hashlib
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path.home() / 'Library/Application Support/TermGPT/workspace.json'
if not path.is_file():
    raise SystemExit('Workspace JSON does not exist; start TermGPT first.')
state = json.loads(path.read_text())
layout = state.get('restoredWorkspace') or {}
def tab(value):
    return {key: value.get(key) for key in ('id', 'bookmarkID')}
normalized = {
    'tabs': [tab(value) for value in layout.get('tabs', [])],
    'active': layout.get('active'),
    'detached': [{'tab': tab(value['tab']), 'frame': value.get('frame')} for value in layout.get('detached') or []],
    'mainFrame': layout.get('mainFrame'),
    'focusedDetached': layout.get('focusedDetached'),
    'libraries': sorted(layout.get('libraries') or [], key=lambda value: value['kind']),
    'focusedLibrary': layout.get('focusedLibrary'),
}
fingerprint = hashlib.sha256(json.dumps(normalized, sort_keys=True).encode()).hexdigest()
print(json.dumps({'mainTabs': len(normalized['tabs']), 'detachedWindows': len(normalized['detached']), 'libraryWindows': len(normalized['libraries']), 'layoutSHA256': fingerprint}))
