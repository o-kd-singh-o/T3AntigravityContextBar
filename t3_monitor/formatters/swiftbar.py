"""SwiftBar and xbar output formatter."""

from t3_monitor.engine import MonitorSnapshot, StatusLevel, format_token_k


def _render_progress_bar(pct: float, width: int = 14) -> str:
    """Render a text progress bar like [███████░░░░░░░]."""
    clamped = max(0.0, min(100.0, pct))
    filled = int(round((clamped / 100.0) * width))
    empty = width - filled
    return f"[{'█' * filled}{'░' * empty}]"


def format_swiftbar(snapshot: MonitorSnapshot) -> str:
    lines: list[str] = []

    # Status indicator dot
    dot_char = "●"
    if snapshot.overall_status == StatusLevel.CRITICAL:
        status_icon = "🔴"
    elif snapshot.overall_status == StatusLevel.WARNING:
        status_icon = "🟡"
    else:
        status_icon = "🟢"

    # Line 1: Header shown directly in the macOS menu bar
    lines.append(f"{dot_char} {snapshot.menu_bar_title} | color={snapshot.overall_color_hex}")
    lines.append("---")

    active = snapshot.active_thread
    if active and active.metrics:
        m = active.metrics
        title_display = active.record.title
        if len(title_display) > 45:
            title_display = title_display[:42] + "..."

        # Active Thread Section
        lines.append(f"Active Thread: {title_display} | size=13 bold=true")
        lines.append(
            f"{_render_progress_bar(m.percentage)} {m.formatted_tokens} / "
            f"{format_token_k(snapshot.config.max_threshold)} ({int(round(m.percentage))}%) | font=Menlo size=12"
        )
        lines.append(f"{status_icon} {m.recommendation} | size=12 color={m.color_hex}")
        lines.append("---")

        # Context Breakdown Submenu
        lines.append("Context Breakdown | size=12")
        lines.append(f"-- Total Active Context: {m.tokens.total_prompt_tokens:,} tokens | font=Menlo")
        lines.append(
            f"-- Cached Context: {m.tokens.cached_tokens:,} tokens ({m.cache_ratio:.1f}%) | font=Menlo"
        )
        lines.append(f"-- New Turn Input: {m.tokens.uncached_tokens:,} tokens | font=Menlo")
        lines.append(f"-- Latest Output: {m.tokens.completion_tokens:,} tokens | font=Menlo")
        if m.tokens.thought_tokens:
            lines.append(f"-- Reasoning / Thought: {m.tokens.thought_tokens:,} tokens | font=Menlo")
        lines.append(f"-- Remaining Headroom: {m.remaining_tokens:,} tokens | font=Menlo")
        lines.append("---")
    elif active:
        title_display = active.record.title[:45]
        lines.append(f"Active Thread: {title_display} | size=13 bold=true")
        lines.append("No token telemetry recorded yet | color=#8b949e")
        lines.append("---")
    else:
        lines.append("No active T3 Code threads found | color=#8b949e")
        lines.append("---")

    # Recent Threads Section (Collapsed by default under a dropdown submenu)
    other_threads = [
        t for t in snapshot.threads
        if not (active and t.record.thread_id == active.record.thread_id)
    ]
    if other_threads:
        lines.append(f"Recent Threads ({len(other_threads)}) | size=12")
        for t in other_threads:
            t_title = t.record.title.strip()
            if len(t_title) > 36:
                t_title = t_title[:33] + "..."
            
            if t.metrics:
                tok_str = t.metrics.formatted_tokens
                color = t.metrics.color_hex
                pct_str = f"{int(round(t.metrics.percentage))}%"
            else:
                tok_str = "—"
                color = "#8b949e"
                pct_str = ""

            status_tag = f"[{t.record.status}]"
            lines.append(f"-- {dot_char} {t_title} ({tok_str}) {status_tag} | color={color} size=11")
            # Submenu details for this thread
            lines.append(f"---- Thread ID: {t.record.thread_id} | font=Menlo size=10")
            lines.append(f"---- Status: {t.record.status} | font=Menlo size=10")
            if t.metrics:
                lines.append(
                    f"---- Prompt Tokens: {t.metrics.tokens.total_prompt_tokens:,} ({pct_str} of limit) | font=Menlo size=10"
                )
                lines.append(
                    f"---- Cached Tokens: {t.metrics.tokens.cached_tokens:,} ({t.metrics.cache_ratio:.1f}%) | font=Menlo size=10"
                )
            lines.append(f"---- Updated: {t.record.updated_at} | font=Menlo size=10")
        lines.append("---")

    # Thresholds info and controls
    warn_k = format_token_k(snapshot.config.warn_threshold)
    max_k = format_token_k(snapshot.config.max_threshold)
    lines.append(f"Thresholds: Warn at {warn_k}, Max at {max_k} | size=10 color=#8b949e")
    lines.append("🔄 Refresh Now | refresh=true")
    lines.append("Open T3 Code | bash=\"/usr/bin/open\" param1=\"-a\" param2=\"T3 Code\" terminal=false")

    return "\n".join(lines)
