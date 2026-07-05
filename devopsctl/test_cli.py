from devopsctl.cli import build_parser


def test_submit_parses():
    args = build_parser().parse_args(
        ["submit", "--scene", "/scenes/test.blend", "--start", "1", "--end", "10"]
    )
    assert args.command == "submit"
    assert args.end == 10


def test_queue_parses():
    args = build_parser().parse_args(["queue"])
    assert args.command == "queue"
