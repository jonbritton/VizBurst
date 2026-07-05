#!/usr/bin/env python3
"""devopsctl — render farm control CLI.
     Jon Britton, Viz Studio

`deadlinecommand` for scheduler state, the deadline/ scripts for job
submission and frame sync, and the AWS CLI (EC2/SSM) for reaching cloud workers.
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

DEADLINE_DIR = Path(__file__).resolve().parent.parent / "deadline"

# "Active" covers both queued and rendering jobs.
JOB_STATUSES = ("Active", "Pending", "Suspended", "Failed")

WORKER_LOG_GLOB = "/var/log/Thinkbox/Deadline10/deadline*.log"


def _run(cmd: list[str]) -> str:
    """Run a command and return stdout; failures surface via main()."""
    return subprocess.run(
        cmd, check=True, capture_output=True, text=True
    ).stdout.strip()


def _deadline(*args: str) -> str:
    return _run(["deadlinecommand", *args])


def _aws(*args: str) -> str:
    return _run(["aws", *args, "--output", "text"])


def _worker_instance_id(worker: str) -> str:
    """Resolve a Deadline worker name to its EC2 instance.
    Cloud workers are named after their EC2 host, the leading label of the instance's private DNS name. 
    Instance IDs are accepted as-is.
    """
    if worker.startswith("i-"):
        return worker
    ids = _aws(
        "ec2", "describe-instances",
        "--filters",
        f"Name=private-dns-name,Values={worker}.*",
        "Name=instance-state-name,Values=running",
        "--query", "Reservations[].Instances[].InstanceId",
    ).split()
    if not ids:
        sys.exit(f"no running instance found for worker {worker!r}")
    if len(ids) > 1:
        sys.exit(f"worker {worker!r} matched instances: {' '.join(ids)}")
    return ids[0]


def cmd_submit(args):
    """Submit through deadline/submit.py: an asset-sync job plus a
    render job that depends on it."""
    job = args.job or Path(args.scene).stem
    subprocess.run(
        [sys.executable, str(DEADLINE_DIR / "submit.py"),
         "--scene", args.scene,
         "--job", job,
         "--frames", f"{args.start}-{args.end}",
         "--group", args.group],
        check=True,
    )


def cmd_queue(args):
    """Job counts by status, straight from the Repository."""
    for status in JOB_STATUSES:
        job_ids = _deadline("-GetJobIdsFilter", f"Status={status}").split()
        print(f"{status.lower():>9}  {len(job_ids)}")


def cmd_logs(args):
    """Tail a cloud worker's render log over SSM."""
    instance = _worker_instance_id(args.worker)
    tail = f'tail -n {args.lines} "$(ls -t {WORKER_LOG_GLOB} | head -1)"'
    command_id = _aws(
        "ssm", "send-command",
        "--instance-ids", instance,
        "--document-name", "AWS-RunShellScript",
        "--parameters", json.dumps({"commands": [tail]}),
        "--query", "Command.CommandId",
    )
    invocation = ["ssm", "get-command-invocation",
                  "--command-id", command_id, "--instance-id", instance]
    while (status := _aws(*invocation, "--query", "Status")) in (
        "Pending", "InProgress", "Delayed"
    ):
        time.sleep(1)
    print(_aws(*invocation, "--query", "StandardOutputContent"))
    if status != "Success":
        error = _aws(*invocation, "--query", "StandardErrorContent")
        sys.exit(f"tail on {instance} finished {status}: {error}")


def cmd_fetch(args):
    """Pull a job's finished frames down from S3 (sync.py pull-frames)."""
    dest = args.dest or str(Path("frames") / args.job)
    subprocess.run(
        [sys.executable, str(DEADLINE_DIR / "sync.py"),
         "pull-frames", args.job, dest],
        check=True,
    )


def build_parser():
    parser = argparse.ArgumentParser(prog="devopsctl",
                                     description="Renderfarm control CLI.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_submit = sub.add_parser("submit", help="Submit job.")
    p_submit.add_argument("--scene", required=True)
    p_submit.add_argument("--start", type=int, default=1)
    p_submit.add_argument("--end", type=int, default=1)
    p_submit.add_argument("--job",
                          help="job name / S3 prefix (default: scene stem)")
    p_submit.add_argument("--group", default="aws-cpu",
                          help="aws-cpu | aws-gpu | (on-prem group)")
    p_submit.set_defaults(func=cmd_submit)

    p_queue = sub.add_parser("queue", help="Show queue depth by job status.")
    p_queue.set_defaults(func=cmd_queue)

    p_logs = sub.add_parser("logs", help="Tail a worker render log.")
    p_logs.add_argument("--worker", required=True,
                        help="Deadline worker name (ip-10-0-1-23) or EC2 "
                             "instance ID")
    p_logs.add_argument("--lines", type=int, default=200)
    p_logs.set_defaults(func=cmd_logs)

    p_fetch = sub.add_parser("fetch", help="Fetch finished frames.")
    p_fetch.add_argument("--job", required=True)
    p_fetch.add_argument("--dest",
                         help="local directory (default: frames/<job>)")
    p_fetch.set_defaults(func=cmd_fetch)

    return parser


def main():
    args = build_parser().parse_args()
    try:
        args.func(args)
    except FileNotFoundError as exc:
        sys.exit(f"required tool not found: {exc.filename}")
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or "").strip()
        prog = exc.cmd[0] if isinstance(exc.cmd, list) else str(exc.cmd)
        sys.exit(detail or f"{prog} exited {exc.returncode}")


if __name__ == "__main__":
    main()
