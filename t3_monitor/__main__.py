"""Command-line interface for T3 Code Context Window Token Monitor."""

import argparse
import sys
import time
from t3_monitor.config import MonitorConfig
from t3_monitor.engine import get_monitor_snapshot
from t3_monitor.formatters.json_fmt import format_json
from t3_monitor.formatters.swiftbar import format_swiftbar
from t3_monitor.formatters.terminal import format_terminal


def main():
    parser = argparse.ArgumentParser(
        description="Monitor T3 Code context window token usage in real time."
    )
    parser.add_argument(
        "--format",
        choices=["swiftbar", "json", "text"],
        default="text",
        help="Output format (default: text)",
    )
    parser.add_argument(
        "--warn",
        type=int,
        default=None,
        help="Warning threshold in tokens (default: 100,000)",
    )
    parser.add_argument(
        "--max",
        type=int,
        default=None,
        help="Hard ceiling threshold in tokens (default: 120,000)",
    )
    parser.add_argument(
        "--watch",
        nargs="?",
        const=5,
        type=int,
        metavar="SECONDS",
        help="Continuously update terminal display every N seconds (default: 5s)",
    )
    parser.add_argument(
        "--state-db",
        type=str,
        default=None,
        help="Custom path to state.sqlite",
    )

    args = parser.parse_args()

    config = MonitorConfig.from_env()
    if args.warn is not None:
        config.warn_threshold = args.warn
    if args.max is not None:
        config.max_threshold = args.max
    if args.state_db:
        config.state_db_path = args.state_db

    if args.watch:
        try:
            while True:
                snapshot = get_monitor_snapshot(config)
                # Clear terminal screen
                print("\033[2J\033[H", end="")
                print(format_terminal(snapshot))
                print(f"\nRefreshing every {args.watch}s (Press Ctrl+C to exit)...")
                time.sleep(args.watch)
        except KeyboardInterrupt:
            print("\nExiting monitor.")
            sys.exit(0)

    snapshot = get_monitor_snapshot(config)

    if args.format == "swiftbar":
        print(format_swiftbar(snapshot))
    elif args.format == "json":
        print(format_json(snapshot))
    else:
        print(format_terminal(snapshot))


if __name__ == "__main__":
    main()
