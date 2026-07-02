#!/usr/bin/env python3
"""devopsctl — render farm control CLI.
     Jon Britton, viz studio
"""

import argparse


def cmd_submit(args):
    print(f"[stub] submit scene={args.scene} frames={args.start}-{args.end}")
    # wrap Deadline job submission (deadlinecommand)


def cmd_queue(args):
    print("[stub] queue depth")
    # query the Deadline web service for queued/active tasks


def cmd_logs(args):
    print(f"[stub] logs for worker={args.worker}")
    # tail a worker pod's render log (kubectl logs)


def cmd_fetch(args):
    print(f"[stub] fetch frames for job={args.job}")
    # pull finished frames from EFS/S3


def build_parser():
    parser = argparse.ArgumentParser(prog="devopsctl",
                                     description="Render farm control CLI.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_submit = sub.add_parser("submit", help="Submit a render job.")
    p_submit.add_argument("--scene", required=True)
    p_submit.add_argument("--start", type=int, default=1)
    p_submit.add_argument("--end", type=int, default=1)
    p_submit.set_defaults(func=cmd_submit)

    p_queue = sub.add_parser("queue", help="Show queue depth.")
    p_queue.set_defaults(func=cmd_queue)

    p_logs = sub.add_parser("logs", help="Tail a worker's render log.")
    p_logs.add_argument("--worker", required=True)
    p_logs.set_defaults(func=cmd_logs)

    p_fetch = sub.add_parser("fetch", help="Fetch finished frames.")
    p_fetch.add_argument("--job", required=True)
    p_fetch.set_defaults(func=cmd_fetch)

    return parser


def main():
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()