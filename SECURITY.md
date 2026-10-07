# Security and privacy

This repository contains source code and synthetic tests, not runtime data.
Credentials are stored in the private local `credentials.json` configuration,
with directory/file permissions 0700/0600. JSON credentials are plain text.
Never commit this file, application state, terminal captures, SSH keys,
environment files, access tokens or real chat exports.

Before publishing changes, run:

```bash
python3 scripts/audit-public.py --tracked
```

The script checks exact Git-tracked files and reports file names and rule names,
never matching secret contents. It is a limited heuristic check, not a security
certification. Review the final diff and commit metadata as well.

For vulnerabilities, use GitHub's private vulnerability reporting if enabled.
Do not put tokens, personal information or private infrastructure details in
public issues. The app's optional redaction does not recognize every secret.
