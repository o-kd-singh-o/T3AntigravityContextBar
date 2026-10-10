import json
import unittest
from t3_monitor.config import MonitorConfig
from t3_monitor.db import ThreadRecord
from t3_monitor.engine import build_snapshot_from_threads
from t3_monitor.formatters.swiftbar import format_swiftbar
from t3_monitor.formatters.json_fmt import format_json
from t3_monitor.proto import TokenUsage


class TestFormatters(unittest.TestCase):
    def setUp(self):
        self.config = MonitorConfig(warn_threshold=100_000, max_threshold=120_000)
        self.threads = [
            ThreadRecord(
                thread_id="t-1",
                title="Design System Migration",
                status="running",
                updated_at="2026-10-10T14:00:00Z",
                session_id="s-1",
                tokens=TokenUsage(
                    total_prompt_tokens=55_000,
                    cached_tokens=45_000,
                    uncached_tokens=10_000,
                    completion_tokens=2_000,
                ),
            ),
            ThreadRecord(
                thread_id="t-2",
                title="Fix Login Bug",
                status="stopped",
                updated_at="2026-10-10T13:00:00Z",
                session_id="s-2",
                tokens=TokenUsage(
                    total_prompt_tokens=105_000,
                    cached_tokens=100_000,
                    uncached_tokens=5_000,
                    completion_tokens=500,
                ),
            ),
        ]
        self.snapshot = build_snapshot_from_threads(self.threads, self.config)

    def test_json_formatter(self):
        output = format_json(self.snapshot)
        data = json.loads(output)
        self.assertIn("active_thread", data)
        self.assertEqual(data["active_thread"]["title"], "Design System Migration")
        self.assertEqual(data["active_thread"]["metrics"]["total_prompt_tokens"], 55_000)
        self.assertEqual(data["overall_status"], "healthy")
        self.assertEqual(len(data["threads"]), 2)

    def test_swiftbar_formatter(self):
        output = format_swiftbar(self.snapshot)
        lines = output.strip().split("\n")
        
        # Line 1 must be the menu bar title with dot and color parameter
        self.assertTrue(lines[0].startswith("● T3: 55.0k (46%)"))
        self.assertIn("color=#3fb950", lines[0])

        # Must have separator
        self.assertIn("---", lines)

        # Must include thread title and token details
        self.assertTrue(any("Design System Migration" in l for l in lines))
        self.assertTrue(any("Fix Login Bug" in l for l in lines))
        self.assertTrue(any("refresh=true" in l for l in lines))


if __name__ == "__main__":
    unittest.main()
