#!/usr/bin/env python3
"""Submit a hybrid render: an asset-sync job plus a render job that
depends on it, so the upload overlaps queue wait and Spot spin-up.

Wraps `deadlinecommand` (must be on PATH — any farm machine has it).

    submit.py --scene /shows/foo/shot010.hip --job foo-shot010 \\
              --group aws-gpu --frames 1-100

TODO(studio): flesh out per-DCC plugin info (this skeleton submits the
scene path straight to the named Deadline plugin) and pool/priority policy.
"""

import argparse
import subprocess
import tempfile
from pathlib import Path

PLUGIN_BY_EXT = {".hip": "Houdini", ".blend": "Blender", ".nk": "Nuke"}
SYNC_SCRIPT = Path(__file__).resolve().parent / "sync.py"


def _job_files(info: dict, plugin: dict) -> list[str]:
    """Write JobInfo/PluginInfo files, return their paths."""
    paths = []
    for payload in (info, plugin):
        f = tempfile.NamedTemporaryFile(
            "w", suffix=".job", delete=False, encoding="utf-8"
        )
        f.write("".join(f"{k}={v}\n" for k, v in payload.items()))
        f.close()
        paths.append(f.name)
    return paths


def _submit(info: dict, plugin: dict) -> str:
    """Run deadlinecommand, return the new JobID."""
    out = subprocess.run(
        ["deadlinecommand", *_job_files(info, plugin)],
        check=True, capture_output=True, text=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("JobID="):
            return line.split("=", 1)[1].strip()
    raise RuntimeError(f"no JobID in deadlinecommand output:\n{out}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--scene", required=True)
    p.add_argument("--job", required=True, help="unique job name / S3 prefix")
    p.add_argument("--frames", default="1-1")
    p.add_argument("--group", default="aws-cpu", help="aws-cpu | aws-gpu | (on-prem group)")
    p.add_argument("--asset-root", help="directory to sync; default = scene's directory")
    args = p.parse_args()

    asset_root = args.asset_root or str(Path(args.scene).parent)
    plugin_name = PLUGIN_BY_EXT.get(Path(args.scene).suffix.lower())
    if plugin_name is None:
        raise SystemExit(f"unknown scene type: {args.scene}")

    # 1. Asset sync as its own job — runs on-prem, overlaps Spot spin-up.
    sync_id = _submit(
        {
            "Plugin": "CommandLine",
            "Name": f"{args.job}-assetsync",
            "Group": "",  # on-prem workers only
        },
        {
            "Executable": "python3",
            "Arguments": f"{SYNC_SCRIPT} push-assets {asset_root} {args.job}",
        },
    )

    # 2. Render job, gated on the sync. Pre/post task scripts handle the
    #    worker-side pull and frame return (see pre_task.py / post_task.py).
    render_id = _submit(
        {
            "Plugin": plugin_name,
            "Name": args.job,
            "Group": args.group,
            "Frames": args.frames,
            "JobDependencies": sync_id,
            "PreTaskScript": str(SYNC_SCRIPT.parent / "pre_task.py"),
            "PostTaskScript": str(SYNC_SCRIPT.parent / "post_task.py"),
            "ExtraInfo0": args.job,  # job/S3 prefix, read back by the hooks
        },
        {
            "SceneFile": args.scene,
            # TODO(studio): plugin-specific keys (OutputDriver, Version, ...)
        },
    )

    print(f"submitted: sync={sync_id} render={render_id}")


if __name__ == "__main__":
    main()
