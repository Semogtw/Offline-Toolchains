#!/usr/bin/env python3
"""Apply the pending GoAnime Mobile HLS checkpoint-reference migration.

The patch is idempotent, formatting-insensitive and limited to the private
checkout used by Offline-Toolchains. Production code must always carry the
store-provided checkpoint reference; test fakes receive an explicit value.
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
    "lib/services/download/hls/hls_package_store.dart",
    r"this\.checkpointEntryReference\s*=\s*'',",
    "required this.checkpointEntryReference,",
    applied_marker="required this.checkpointEntryReference,",
)

patch_once(
    "lib/services/download/hls/hls_transfer_models.dart",
    r"this\.checkpointEntryReference\s*=\s*'',",
    "required this.checkpointEntryReference,",
    applied_marker="required this.checkpointEntryReference,",
)

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

queue_path = Path("lib/services/download/download_queue_manager_hls.dart")
queue_text = queue_path.read_text(encoding="utf-8")
if "checkpointPath: result.checkpointEntryReference," not in queue_text:
    queue_patterns = (
        r"checkpointPath:\s*result\.checkpointEntryReference\.isEmpty\s*"
        r"\?\s*path\.join\(result\.packageRootReference,\s*'checkpoint\.json'\)\s*"
        r":\s*result\.checkpointEntryReference,",
        r"checkpointPath:\s*path\.join\(\s*"
        r"result\.packageRootReference,\s*"
        r"'checkpoint\.json',\s*"
        r"\),",
    )
    for pattern in queue_patterns:
        queue_text, count = re.subn(
            pattern,
            "checkpointPath: result.checkpointEntryReference,",
            queue_text,
            count=1,
            flags=re.S | re.M,
        )
        if count == 1:
            queue_path.write_text(queue_text, encoding="utf-8")
            break
    else:
        raise PatchError(f"{queue_path}: checkpoint persistence block not found")


def find_call_close(text: str, open_index: int) -> int:
    depth = 0
    quote: str | None = None
    escaped = False
    line_comment = False
    block_comment = False
    index = open_index
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
            index += 1
            continue
        if block_comment:
            if char == "*" and next_char == "/":
                block_comment = False
                index += 2
                continue
            index += 1
            continue
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if char == "/" and next_char == "/":
            line_comment = True
            index += 2
            continue
        if char == "/" and next_char == "*":
            block_comment = True
            index += 2
            continue
        if char in "'\"":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise PatchError("unterminated Dart constructor call")


def add_test_argument(text: str, constructor: str, before: str) -> tuple[str, int]:
    needle = f"{constructor}("
    cursor = 0
    changed = 0
    while True:
        start = text.find(needle, cursor)
        if start < 0:
            break
        open_index = start + len(constructor)
        close_index = find_call_close(text, open_index)
        block = text[open_index + 1 : close_index]
        if "checkpointEntryReference:" not in block:
            match = re.search(rf"(?m)^(\s*){re.escape(before)}:", block)
            if match is None:
                raise PatchError(
                    f"{constructor}: could not place checkpoint argument before {before}"
                )
            insertion = (
                f"{match.group(1)}checkpointEntryReference: "
                "'checkpoint.json',\n"
            )
            original_length = len(block)
            block = block[: match.start()] + insertion + block[match.start() :]
            text = text[: open_index + 1] + block + text[close_index:]
            close_index += len(block) - original_length
            changed += 1
        cursor = close_index + 1
    return text, changed


constructor_updates = 0
for test_path in Path("test").rglob("*.dart"):
    original = test_path.read_text(encoding="utf-8")
    updated, completed = add_test_argument(
        original,
        "HlsTransferCompleted",
        "committedBytes",
    )
    updated, promotions = add_test_argument(
        updated,
        "HlsPackagePromotion",
        "packageRootReference",
    )
    if updated != original:
        test_path.write_text(updated, encoding="utf-8")
    constructor_updates += completed + promotions

print(
    "GoAnime HLS checkpoint-reference migration applied; "
    f"updated {constructor_updates} test constructor calls."
)
