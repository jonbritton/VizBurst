#!/usr/bin/env python3
"""Asset/frame movement between the studio and the S3 transfer lane.

Four verbs, matching the four legs of a hybrid render:

    push-assets   on-prem  -> S3      (submit time; delta via manifest)
    pull-assets   S3       -> worker  (task start; cached on /scratch)
    push-frames   worker   -> S3      (post task)
    pull-frames   S3       -> on-prem (cron or post job)

Transfers shell out to the AWS CLI (present on workers via the AMI and on
the studio submit host) rather than importing boto3 into Deadline's
embedded interpreter. Buckets come from the environment:

    ASSETS_BUCKET / FRAMES_BUCKET   (values from `tofu output`)

Layout in the assets bucket:
    objects/<sha256>            content-addressed blob store
    jobs/<job>/manifest.json    what a job needs, and where it goes
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

import manifest

SCRATCH = Path(os.environ.get("RENDER_SCRATCH", "/scratch"))


def _bucket(env_var: str) -> str:
    value = os.environ.get(env_var)
    if not value:
        sys.exit(f"ERROR: {env_var} is not set")
    return value


def _aws(*args: str) -> None:
    subprocess.run(["aws", "s3", *args, "--no-progress"], check=True)


def _remote_object_hashes(bucket: str) -> set[str]:
    """Hashes already present in the blob store (one LIST, not N HEADs)."""
    out = subprocess.run(
        ["aws", "s3api", "list-objects-v2", "--bucket", bucket,
         "--prefix", "objects/", "--query", "Contents[].Key", "--output", "text"],
        check=True, capture_output=True, text=True,
    ).stdout.split()
    return {key.rpartition("/")[2] for key in out if "/" in key}


def push_assets(asset_root: str, job: str) -> None:
    """Delta-upload a job's assets and publish its manifest."""
    bucket = _bucket("ASSETS_BUCKET")
    local = manifest.build(asset_root)
    missing = manifest.diff(local, _remote_object_hashes(bucket))

    print(f"{len(local)} assets, {len(missing)} new -> s3://{bucket}")
    for rel, meta in missing.items():
        src = Path(asset_root) / rel
        _aws("cp", str(src), f"s3://{bucket}/objects/{meta['sha256']}")

    manifest.save(local, "/tmp/manifest.json")
    _aws("cp", "/tmp/manifest.json", f"s3://{bucket}/jobs/{job}/manifest.json")


def pull_assets(job: str) -> Path:
    """Materialize a job's assets on the worker's scratch volume. Idempotent:
    blobs are cached under objects/ and hard-linked into the job tree, so
    tasks 2..N of a job (or a sibling shot) re-download nothing."""
    bucket = _bucket("ASSETS_BUCKET")
    cache = SCRATCH / "objects"
    dest = SCRATCH / "assets" / job
    cache.mkdir(parents=True, exist_ok=True)

    _aws("cp", f"s3://{bucket}/jobs/{job}/manifest.json", "/tmp/manifest.json")
    for rel, meta in manifest.load("/tmp/manifest.json").items():
        blob = cache / meta["sha256"]
        if not blob.exists():
            _aws("cp", f"s3://{bucket}/objects/{meta['sha256']}", str(blob))
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            os.link(blob, target)

    print(f"assets ready at {dest}")
    return dest


def push_frames(frames_dir: str, job: str) -> None:
    bucket = _bucket("FRAMES_BUCKET")
    _aws("sync", frames_dir, f"s3://{bucket}/jobs/{job}/")


def pull_frames(job: str, dest: str) -> None:
    bucket = _bucket("FRAMES_BUCKET")
    Path(dest).mkdir(parents=True, exist_ok=True)
    _aws("sync", f"s3://{bucket}/jobs/{job}/", dest)
    # S3 copies expire via bucket lifecycle (14 days) — no cleanup here.


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="verb", required=True)

    s = sub.add_parser("push-assets")
    s.add_argument("asset_root")
    s.add_argument("job")

    s = sub.add_parser("pull-assets")
    s.add_argument("job")

    s = sub.add_parser("push-frames")
    s.add_argument("frames_dir")
    s.add_argument("job")

    s = sub.add_parser("pull-frames")
    s.add_argument("job")
    s.add_argument("dest")

    args = p.parse_args()
    if args.verb == "push-assets":
        push_assets(args.asset_root, args.job)
    elif args.verb == "pull-assets":
        pull_assets(args.job)
    elif args.verb == "push-frames":
        push_frames(args.frames_dir, args.job)
    elif args.verb == "pull-frames":
        pull_frames(args.job, args.dest)


if __name__ == "__main__":
    main()
