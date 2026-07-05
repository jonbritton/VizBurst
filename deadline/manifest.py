#!/usr/bin/env python3
"""Content-addressed asset manifest.

The unit of transfer between the studio and AWS. A manifest maps each
asset's job-relative path to its sha256 + size; objects live in S3 under
their hash (objects/<sha256>), so two shots sharing a texture share one
upload, and "what needs uploading" is a set difference, not a re-scan.

Stdlib only — this runs inside Deadline's embedded Python and on workers.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

CHUNK = 1024 * 1024


def hash_file(path: Path) -> str:
    """sha256 of a file, streamed."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(CHUNK):
            h.update(chunk)
    return h.hexdigest()


def build(asset_root: str | Path) -> dict:
    """Walk asset_root and return {relpath: {"sha256": ..., "size": ...}}."""
    root = Path(asset_root)
    entries = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        entries[rel] = {"sha256": hash_file(path), "size": path.stat().st_size}
    return entries


def diff(local: dict, remote_hashes: set[str]) -> dict:
    """Entries of `local` whose objects are not already in the remote store."""
    return {
        rel: meta
        for rel, meta in local.items()
        if meta["sha256"] not in remote_hashes
    }


def save(manifest: dict, path: str | Path) -> None:
    Path(path).write_text(json.dumps(manifest, indent=1, sort_keys=True))


def load(path: str | Path) -> dict:
    return json.loads(Path(path).read_text())
