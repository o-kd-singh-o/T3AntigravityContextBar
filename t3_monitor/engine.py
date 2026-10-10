"""Context window monitoring engine and threshold calculator."""

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional

from t3_monitor.config import MonitorConfig
from t3_monitor.db import T3DatabaseReader, ThreadRecord
from t3_monitor.proto import TokenUsage


class StatusLevel(str, Enum):
    HEALTHY = "healthy"
    WARNING = "warning"
    CRITICAL = "critical"


COLOR_MAP = {
    StatusLevel.HEALTHY: ("#3fb950", "green"),
    StatusLevel.WARNING: ("#d29922", "yellow"),
    StatusLevel.CRITICAL: ("#f85149", "red"),
}


@dataclass
class TokenMetrics:
    tokens: TokenUsage
    status_level: StatusLevel
    color_hex: str
    color_name: str
    percentage: float
    remaining_tokens: int
    cache_ratio: float
    formatted_tokens: str
    recommendation: str


@dataclass
class ThreadContextSnapshot:
    record: ThreadRecord
    metrics: Optional[TokenMetrics]


@dataclass
class MonitorSnapshot:
    active_thread: Optional[ThreadContextSnapshot]
    threads: List[ThreadContextSnapshot]
    overall_status: StatusLevel
    overall_color_hex: str
    menu_bar_title: str
    timestamp: str
    config: MonitorConfig


def format_token_k(count: int) -> str:
    """Format token count nicely, e.g. 5000 -> 5.0k, 102590 -> 102.6k."""
    if count >= 1_000_000:
        return f"{count / 1_000_000:.1f}M"
    if count >= 1_000:
        return f"{count / 1_000:.1f}k"
    return str(count)


def calculate_token_metrics(tokens: TokenUsage, config: MonitorConfig) -> TokenMetrics:
    total = tokens.total_prompt_tokens
    pct = (total / config.max_threshold) * 100 if config.max_threshold > 0 else 0.0
    remaining = max(0, config.max_threshold - total)
    cache_pct = (tokens.cached_tokens / total * 100) if total > 0 else 0.0

    if total >= config.max_threshold:
        level = StatusLevel.CRITICAL
        rec = f"Ceiling reached (≥{format_token_k(config.max_threshold)}) — hand off immediately"
    elif total >= config.warn_threshold:
        level = StatusLevel.WARNING
        rec = f"Warning zone (≥{format_token_k(config.warn_threshold)}) — plan handoff soon"
    else:
        level = StatusLevel.HEALTHY
        rec = "Context healthy — continue work normally"

    color_hex, color_name = COLOR_MAP[level]

    return TokenMetrics(
        tokens=tokens,
        status_level=level,
        color_hex=color_hex,
        color_name=color_name,
        percentage=pct,
        remaining_tokens=remaining,
        cache_ratio=cache_pct,
        formatted_tokens=format_token_k(total),
        recommendation=rec,
    )


def build_snapshot_from_threads(threads: List[ThreadRecord], config: MonitorConfig) -> MonitorSnapshot:
    thread_snapshots: List[ThreadContextSnapshot] = []
    active_snapshot: Optional[ThreadContextSnapshot] = None

    for t in threads:
        metrics = calculate_token_metrics(t.tokens, config) if t.tokens else None
        snap = ThreadContextSnapshot(record=t, metrics=metrics)
        thread_snapshots.append(snap)
        if active_snapshot is None and (t.status == "running" or len(thread_snapshots) == 1):
            active_snapshot = snap

    # Fallback to first thread if active not set
    if not active_snapshot and thread_snapshots:
        active_snapshot = thread_snapshots[0]

    if active_snapshot and active_snapshot.metrics:
        overall_status = active_snapshot.metrics.status_level
        overall_hex = active_snapshot.metrics.color_hex
        pct_int = int(round(active_snapshot.metrics.percentage))
        menu_title = f"T3: {active_snapshot.metrics.formatted_tokens} ({pct_int}%)"
    else:
        overall_status = StatusLevel.HEALTHY
        overall_hex = COLOR_MAP[StatusLevel.HEALTHY][0]
        menu_title = "T3: Idle"

    return MonitorSnapshot(
        active_thread=active_snapshot,
        threads=thread_snapshots,
        overall_status=overall_status,
        overall_color_hex=overall_hex,
        menu_bar_title=menu_title,
        timestamp=datetime.now(timezone.utc).isoformat(),
        config=config,
    )


def get_monitor_snapshot(config: Optional[MonitorConfig] = None) -> MonitorSnapshot:
    """Fetch current state and construct full snapshot."""
    cfg = config or MonitorConfig.from_env()
    reader = T3DatabaseReader(cfg)
    threads = reader.get_threads()
    return build_snapshot_from_threads(threads, cfg)
