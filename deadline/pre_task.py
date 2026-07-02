"""Deadline Pre-Task script: stage the job's assets onto worker scratch.

Runs inside the Deadline Worker's embedded Python before every task;
pull_assets is cached, so only the first task on an instance transfers.
Wired up by submit.py (PreTaskScript=...).

Deadline calls __main__ with the plugin object — see the Deadline
Scripting reference for DeadlinePlugin API details.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync  # noqa: E402


def __main__(deadline_plugin):
    job = deadline_plugin.GetJob().JobExtraInfo0  # set by submit.py
    dest = sync.pull_assets(job)
    # Expose the local asset root to the render plugin.
    deadline_plugin.SetProcessEnvironmentVariable("JOB_ASSET_ROOT", str(dest))
