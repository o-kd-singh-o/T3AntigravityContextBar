"""Configuration for T3 Code Context Window Monitor."""

import os
from dataclasses import dataclass


@dataclass
class MonitorConfig:
    warn_threshold: int = 100_000
    max_threshold: int = 120_000
    state_db_path: str = os.path.expanduser("~/.t3/userdata/state.sqlite")
    conversations_dir_pattern: str = os.path.expanduser(
        "~/.t3/userdata/providers/antigravity/*/antigravity-acp/conversations"
    )
    poll_interval_seconds: int = 10
    max_recent_threads: int = 8

    @classmethod
    def from_env(cls) -> "MonitorConfig":
        """Load configuration from environment variables if present."""
        warn_th = int(os.environ.get("T3_WARN_THRESHOLD", 100_000))
        max_th = int(os.environ.get("T3_MAX_THRESHOLD", 120_000))
        poll_int = int(os.environ.get("T3_POLL_INTERVAL", 10))
        state_path = os.environ.get("T3_STATE_DB", os.path.expanduser("~/.t3/userdata/state.sqlite"))
        conv_pattern = os.environ.get(
            "T3_CONV_DIR_PATTERN",
            os.path.expanduser("~/.t3/userdata/providers/antigravity/*/antigravity-acp/conversations"),
        )
        return cls(
            warn_threshold=warn_th,
            max_threshold=max_th,
            state_db_path=state_path,
            conversations_dir_pattern=conv_pattern,
            poll_interval_seconds=poll_int,
        )
