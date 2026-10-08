# Bundled lrzsz 0.13.1

Official source: https://ohse.de/uwe/releases/lrzsz-0.13.1.tar.gz
Project: https://ohse.de/uwe/software/lrzsz.html
License: GPL-2.0-or-later; see COPYING and source notices. This is a separate executable, not linked into TermGPT. Complete corresponding upstream source is included in this repository. No upstream C source modifications are made.

`../../scripts/build-zmodem.sh` checks clang/make/macOS, builds ARM or Intel helper executables and removes temporary build sources. The package script bundles these helpers and COPYING. TermGPT invokes receive in restricted mode in a private staging directory, disables syslog, and does not enable remote command execution. Refer to the main README for file transfer usage.
