"""JSON output formatter for T3 Monitor."""

import json
from t3_monitor.engine import MonitorSnapshot, ThreadContextSnapshot


def _serialize_thread_snapshot(snap: ThreadContextSnapshot) -> dict:
    item = {
        "thread_id": snap.record.thread_id,
        "title": snap.record.title,
        "status": snap.record.status,
        "updated_at": snap.record.updated_at,
        "session_id": snap.record.session_id,
    }
    if snap.metrics:
        m = snap.metrics
        item["metrics"] = {
            "total_prompt_tokens": m.tokens.total_prompt_tokens,
            "cached_tokens": m.tokens.cached_tokens,
            "uncached_tokens": m.tokens.uncached_tokens,
            "completion_tokens": m.tokens.completion_tokens,
            "thought_tokens": m.tokens.thought_tokens,
            "percentage": round(m.percentage, 1),
            "remaining_tokens": m.remaining_tokens,
            "cache_ratio": round(m.cache_ratio, 1),
            "status_level": m.status_level.value,
            "color_hex": m.color_hex,
            "formatted_tokens": m.formatted_tokens,
            "recommendation": m.recommendation,
        }
    else:
        item["metrics"] = None
    return item


def format_json(snapshot: MonitorSnapshot, indent: int = 2) -> str:
    data = {
        "timestamp": snapshot.timestamp,
        "overall_status": snapshot.overall_status.value,
        "overall_color_hex": snapshot.overall_color_hex,
        "menu_bar_title": snapshot.menu_bar_title,
        "config": {
            "warn_threshold": snapshot.config.warn_threshold,
            "max_threshold": snapshot.config.max_threshold,
            "poll_interval_seconds": snapshot.config.poll_interval_seconds,
        },
        "active_thread": _serialize_thread_snapshot(snapshot.active_thread) if snapshot.active_thread else None,
        "threads": [_serialize_thread_snapshot(t) for t in snapshot.threads],
    }
    return json.dumps(data, indent=indent)
