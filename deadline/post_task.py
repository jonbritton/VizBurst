"""Deadline Post-Task script: ship the task's rendered frames to S3.

Runs inside the Deadline Worker's embedded Python after every task.
Wired up by submit.py (PostTaskScript=...). Frames land under
s3://<FRAMES_BUCKET>/jobs/<job>/ and expire via bucket lifecycle after
the on-prem pull (sync.py pull-frames) has fetched them.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync  # noqa: E402


def __main__(deadline_plugin):
    job = deadline_plugin.GetJob().JobExtraInfo0  # set by submit.py
    frames_dir = os.environ.get(
        "JOB_FRAMES_DIR", str(sync.SCRATCH / "frames" / job)
    )
    if Path(frames_dir).is_dir():
        sync.push_frames(frames_dir, job)
    else:
        deadline_plugin.LogWarning(f"no frames dir at {frames_dir}; nothing pushed")
