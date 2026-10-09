#!/usr/bin/env python3
"""Apply the narrow xrdp reactivation compatibility change to pinned FreeRDP."""
import sys
from pathlib import Path

if sys.version_info < (3, 8) or len(sys.argv) != 2:
    raise SystemExit('Requires Python 3.8+: patch-freerdp.py FREERDP_SOURCE')
path = Path(sys.argv[1]) / 'libfreerdp/core/update.c'
source = path.read_text()
old = '''\tif (!rdp_has_reached_state(update->context->rdp, CONNECTION_STATE_ACTIVE))
\t\treturn FALSE;

\tif (!Stream_CheckAndLogRequiredLength(TAG, s, 2))'''
new = '''\t/* Older xrdp sends desktop updates during resize reactivation, before
\t * its final synchronization/font-map PDUs. Only an already active,
\t * authenticated session may take this compatibility path. Discard obsolete
\t * updates until reactivation completes. Normal decoding stays unchanged. */
\tif (!rdp_has_reached_state(context->rdp, CONNECTION_STATE_ACTIVE))
\t{
\t\tconst CONNECTION_STATE state = rdp_get_state(context->rdp);
\t\tif (!context->rdp->was_deactivated || !context->gdi ||
\t\t    state < CONNECTION_STATE_FINALIZATION_CLIENT_SYNC ||
\t\t    state > CONNECTION_STATE_FINALIZATION_CLIENT_FONT_MAP)
\t\t\treturn FALSE;
\t\tStream_Seek(s, Stream_GetRemainingLength(s));
\t\treturn TRUE;
\t}

\tif (!Stream_CheckAndLogRequiredLength(TAG, s, 2))'''
if new not in source and source.count(old) != 1:
    raise SystemExit('Pinned FreeRDP update guard changed; review patch before building')
path.write_text(source.replace(old, new))

# Expose per-helper audio state and mute without changing certificate/authentication code.
mac = Path(sys.argv[1]) / 'channels/rdpsnd/client/mac/rdpsnd_mac.m'
source = mac.read_text()
marker = '/* TermGPT per-process audio controls */'
if marker not in source:
    anchor = '#include "rdpsnd_main.h"'
    controls = """/* TermGPT per-process audio controls */
#include <stdatomic.h>
static atomic_bool termgptMuted;
static void (*termgptAudioState)(const char*);
void termgpt_rdpsnd_set_muted(int muted) { atomic_store(&termgptMuted, muted != 0); }
void termgpt_rdpsnd_set_state_callback(void (*callback)(const char*)) { termgptAudioState = callback; }
"""
    play = '\t\tif (!mac->isOpen)\n\t\t\treturn 0;'
    if source.count(anchor) != 1 or source.count(play) != 1:
        raise SystemExit('Pinned macOS audio backend changed; review audio controls')
    source = source.replace(anchor, anchor + '\n' + controls)
    source = source.replace(play, '\t\tif (!mac->isOpen) { if (termgptAudioState) termgptAudioState("error"); return 0; }\n\t\tif (termgptAudioState) termgptAudioState("playing");\n\t\tif (atomic_load(&termgptMuted)) return 100;')
    source = source.replace('mac->isOpen = FALSE;', 'mac->isOpen = FALSE; if (termgptAudioState) termgptAudioState("idle");')
    source = source.replace('mac->isOpen = TRUE;', 'mac->isOpen = TRUE; if (termgptAudioState) termgptAudioState("ready");')
    source = source.replace('WLog_ERR(TAG, "Failed to start audio player %s",', 'if (termgptAudioState) termgptAudioState("error");\n\t\t\tWLog_ERR(TAG, "Failed to start audio player %s",')
    mac.write_text(source)
