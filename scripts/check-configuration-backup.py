#!/usr/bin/env python3
"""Inspect a backup without printing its contents; optionally compare a workspace."""
import argparse
import base64
import hashlib
import json
import pathlib
import sys


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup", type=pathlib.Path)
    parser.add_argument("--compare", type=pathlib.Path, help="Compare with a workspace JSON without printing private data")
    args = parser.parse_args()
    if sys.version_info < (3, 8):
        raise SystemExit("Python 3.8 or newer is required")
    if args.backup.stat().st_size > 64 * 1024 * 1024:
        raise SystemExit("Backup exceeds the supported size")
    envelope = json.loads(args.backup.read_bytes())
    if envelope.get("format") != "TermGPT.backup" or envelope.get("version") != 1:
        raise SystemExit("Unsupported backup format")
    print("Encrypted:", envelope.get("encrypted") is True)
    print("File permissions:", oct(args.backup.stat().st_mode & 0o777))
    if envelope.get("encrypted") is True:
        if args.compare:
            raise SystemExit("Encrypted backups must be restored in TermGPT before comparison")
        return
    document = json.loads(base64.b64decode(envelope["content"], validate=True))
    if document.get("format") != "TermGPT.configuration" or document.get("version") != 1:
        raise SystemExit("Unsupported configuration format")
    state = document["state"]
    print("Contains credential store:", document.get("credentials") is not None)
    for name in ("bookmarks", "folders", "savedNotes", "savedCommands", "chats"):
        print(name + ":", len(state.get(name) or []))
    print("Configuration SHA256:", fingerprint(state))
    if args.compare:
        same = fingerprint(state) == fingerprint(json.loads(args.compare.read_bytes()))
        print("Matches workspace:", same)
        if not same:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
