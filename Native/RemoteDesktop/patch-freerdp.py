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
if new in source:
    raise SystemExit(0)
if source.count(old) != 1:
    raise SystemExit('Pinned FreeRDP update guard changed; review patch before building')
path.write_text(source.replace(old, new))
