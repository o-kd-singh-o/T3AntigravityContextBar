"""ANSI colored terminal output formatter for CLI usage."""

from t3_monitor.engine import MonitorSnapshot, StatusLevel, format_token_k


def _render_ascii_bar(pct: float, width: int = 24) -> str:
    clamped = max(0.0, min(100.0, pct))
    filled = int(round((clamped / 100.0) * width))
    empty = width - filled
    return f"[{'#' * filled}{'-' * empty}]"


def format_terminal(snapshot: MonitorSnapshot) -> str:
    # ANSI escape codes
    reset = "\033[0m"
    bold = "\033[1m"
    dim = "\033[2m"
    
    if snapshot.overall_status == StatusLevel.CRITICAL:
        status_color = "\033[31m"  # red
    elif snapshot.overall_status == StatusLevel.WARNING:
        status_color = "\033[33m"  # yellow
    else:
        status_color = "\033[32m"  # green

    lines: list[str] = [
        f"{bold}=== T3 Code Context Window Token Monitor ==={reset}",
        f"{dim}Checked at: {snapshot.timestamp}{reset}",
        "",
    ]

    active = snapshot.active_thread
    if active and active.metrics:
        m = active.metrics
        lines.extend([
            f"{bold}Active Thread:{reset} {active.record.title}",
            f"{bold}Status:{reset} {status_color}{m.status_level.value.upper()}{reset} ({m.recommendation})",
            f"{bold}Usage:{reset}  {status_color}{_render_ascii_bar(m.percentage)}{reset} "
            f"{m.formatted_tokens} / {format_token_k(snapshot.config.max_threshold)} ({m.percentage:.1f}%)",
            "",
            f"{bold}Breakdown:{reset}",
            f"  - Total Prompt Context: {m.tokens.total_prompt_tokens:,} tokens",
            f"  - Cached Context:       {m.tokens.cached_tokens:,} tokens ({m.cache_ratio:.1f}%)",
            f"  - New Turn Input:       {m.tokens.uncached_tokens:,} tokens",
            f"  - Latest Output:        {m.tokens.completion_tokens:,} tokens",
            f"  - Remaining Headroom:   {m.remaining_tokens:,} tokens",
        ])
    elif active:
        lines.append(f"{bold}Active Thread:{reset} {active.record.title} (No telemetry recorded)")
    else:
        lines.append(f"{dim}No active T3 Code threads found.{reset}")

    other_threads = [
        t for t in snapshot.threads
        if not (active and t.record.thread_id == active.record.thread_id)
    ]
    if other_threads:
        lines.append("")
        lines.append(f"{bold}Other Recent Threads:{reset}")
        for t in other_threads:
            if t.metrics:
                tok = f"{t.metrics.formatted_tokens:>6s} ({t.metrics.percentage:4.1f}%)"
            else:
                tok = "     —      "
            status_tag = f"[{t.record.status}]"
            lines.append(f"  {tok}  {status_tag:9s}  {t.record.title[:45]}")

    lines.append("")
    lines.append(f"{dim}Ceiling: {format_token_k(snapshot.config.max_threshold)} | Warn: {format_token_k(snapshot.config.warn_threshold)}{reset}")
    return "\n".join(lines)
