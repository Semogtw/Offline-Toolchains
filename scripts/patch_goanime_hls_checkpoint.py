#!/usr/bin/env python3
"""Apply the pending GoAnime Mobile HLS checkpoint-reference migration.

The patch is intentionally idempotent and insensitive to Dart formatting.
It is executed only against the private checkout inside Offline-Toolchains CI.
"""

from __future__ import annotations

import re
from pathlib import Path


class PatchError(RuntimeError):
    pass


def patch_once(
    path: str,
    pattern: str,
    replacement: str,
    *,
    applied_marker: str,
) -> None:
    target = Path(path)
    text = target.read_text(encoding="utf-8")
    if applied_marker in text:
        return
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise PatchError(f"{path}: expected one structural match, found {count}")
    target.write_text(updated, encoding="utf-8")


patch_once(
    "lib/services/download/hls/filesystem_hls_package_store.dart",
    r"(playlistEntryReference:\s*path\.join\(complete\.path,\s*_playlist\),\s*\n)(\s*\);)",
    r"\1        checkpointEntryReference: path.join(complete.path, _checkpoint),\n\2",
    applied_marker="checkpointEntryReference: path.join(complete.path, _checkpoint)",
)

patch_once(
    "lib/services/download/hls/saf_hls_package_store.dart",
    r"(final playlist = await _requireSafFile\(\s*"
    r"treeUri: package\.parent\.treeUri,\s*"
    r"parentUri: finalUri,\s*"
    r"displayName: _safPlaylist,\s*"
    r"\);)(\s*\n\s*if \(!await _access\.deleteDocument\(marker\.uri\)\))",
    r"\1\n      final checkpoint = await _requireSafFile(\n"
    r"        treeUri: package.parent.treeUri,\n"
    r"        parentUri: finalUri,\n"
    r"        displayName: _safCheckpoint,\n"
    r"      );\2",
    applied_marker="final checkpoint = await _requireSafFile(",
)

patch_once(
    "lib/services/download/hls/saf_hls_package_store.dart",
    r"(playlistEntryReference:\s*playlist\.uri,\s*\n)(\s*\);)",
    r"\1        checkpointEntryReference: checkpoint.uri,\n\2",
    applied_marker="checkpointEntryReference: checkpoint.uri",
)

patch_once(
    "lib/services/download/hls/hls_download_engine_support.dart",
    r"(playlistEntryReference:\s*promotion\.playlistEntryReference,\s*\n)(\s*committedBytes:)",
    r"\1        checkpointEntryReference: promotion.checkpointEntryReference,\n\2",
    applied_marker="checkpointEntryReference: promotion.checkpointEntryReference",
)

patch_once(
    "lib/services/download/download_queue_manager_hls.dart",
    r"checkpointPath:\s*path\.join\(\s*"
    r"result\.packageRootReference,\s*"
    r"'checkpoint\.json',\s*"
    r"\),",
    "checkpointPath: result.checkpointEntryReference.isEmpty\n"
    "                ? path.join(result.packageRootReference, 'checkpoint.json')\n"
    "                : result.checkpointEntryReference,",
    applied_marker="checkpointPath: result.checkpointEntryReference.isEmpty",
)

print("GoAnime HLS checkpoint-reference migration applied or already present.")
