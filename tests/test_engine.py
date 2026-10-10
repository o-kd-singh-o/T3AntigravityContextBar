import unittest
from t3_monitor.config import MonitorConfig
from t3_monitor.db import ThreadRecord
from t3_monitor.proto import TokenUsage
from t3_monitor.engine import (
    calculate_token_metrics,
    build_snapshot_from_threads,
    StatusLevel,
)


class TestEngine(unittest.TestCase):
    def setUp(self):
        self.config = MonitorConfig(warn_threshold=100_000, max_threshold=120_000)

    def test_healthy_metrics(self):
        tokens = TokenUsage(
            total_prompt_tokens=50_000,
            cached_tokens=40_000,
            uncached_tokens=10_000,
            completion_tokens=1_000,
        )
        metrics = calculate_token_metrics(tokens, self.config)
        self.assertEqual(metrics.status_level, StatusLevel.HEALTHY)
        self.assertEqual(metrics.color_hex, "#3fb950")  # GitHub green
        self.assertEqual(metrics.color_name, "green")
        self.assertAlmostEqual(metrics.percentage, 41.7, places=1)
        self.assertEqual(metrics.remaining_tokens, 70_000)
        self.assertAlmostEqual(metrics.cache_ratio, 80.0, places=1)

    def test_warning_metrics(self):
        tokens = TokenUsage(
            total_prompt_tokens=105_000,
            cached_tokens=100_000,
            uncached_tokens=5_000,
            completion_tokens=800,
        )
        metrics = calculate_token_metrics(tokens, self.config)
        self.assertEqual(metrics.status_level, StatusLevel.WARNING)
        self.assertEqual(metrics.color_hex, "#d29922")  # GitHub amber
        self.assertEqual(metrics.color_name, "yellow")
        self.assertAlmostEqual(metrics.percentage, 87.5, places=1)
        self.assertEqual(metrics.remaining_tokens, 15_000)

    def test_critical_metrics(self):
        tokens = TokenUsage(
            total_prompt_tokens=125_000,
            cached_tokens=115_000,
            uncached_tokens=10_000,
            completion_tokens=500,
        )
        metrics = calculate_token_metrics(tokens, self.config)
        self.assertEqual(metrics.status_level, StatusLevel.CRITICAL)
        self.assertEqual(metrics.color_hex, "#f85149")  # GitHub red
        self.assertEqual(metrics.color_name, "red")
        self.assertGreaterEqual(metrics.percentage, 100.0)
        self.assertEqual(metrics.remaining_tokens, 0)

    def test_snapshot_active_thread_selection(self):
        threads = [
            ThreadRecord(
                thread_id="t-running",
                title="Running Thread",
                status="running",
                updated_at="2026-10-10T12:00:00Z",
                session_id="s1",
                tokens=TokenUsage(60_000, 50_000, 10_000, 500),
            ),
            ThreadRecord(
                thread_id="t-stopped",
                title="Stopped Thread",
                status="stopped",
                updated_at="2026-10-10T11:00:00Z",
                session_id="s2",
                tokens=TokenUsage(110_000, 100_000, 10_000, 500),
            ),
        ]
        snapshot = build_snapshot_from_threads(threads, self.config)
        self.assertIsNotNone(snapshot.active_thread)
        self.assertEqual(snapshot.active_thread.record.thread_id, "t-running")
        self.assertEqual(snapshot.overall_status, StatusLevel.HEALTHY)
        self.assertEqual(snapshot.menu_bar_title, "T3: 60.0k (50%)")


if __name__ == "__main__":
    unittest.main()
