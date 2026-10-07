# Source publication review

Initial publication uses a new Git repository with no imported local or vendor
Git history. Commit identity is a generic project identity, without a personal
email or machine name. Upstream public attribution and MIT license are retained.

Included: Swift sources, synthetic tests, build/helper scripts, package manifests,
MIT licenses, documentation and the reviewed PNG icon source.

Excluded: local paths and local validation notes, original requirements document,
logs, build caches, executables/ZIPs, generated ICNS metadata, screenshots,
application state, account records, SSH configuration, Keychain data and secrets.
The export process never reads Keychain or the app's runtime state directory.

`export-public.py` uses an explicit allowlist. `audit-public.py` checks forbidden
files, personal home paths, first-party email addresses, private network addresses,
credential-like values, private key material and actual PNG text/EXIF chunks.
Tests contain deliberately fake credential samples; no live credentials are used.

Checks reduce publication risk but cannot prove the absence of all secrets.
The scope is exact committed files and commit metadata, not unrelated data on
a developer's computer or future contributions.
