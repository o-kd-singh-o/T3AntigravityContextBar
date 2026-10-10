import os
import sqlite3
import tempfile
import unittest
from t3_monitor.config import MonitorConfig
from t3_monitor.db import T3DatabaseReader, ThreadRecord
from t3_monitor.proto import encode_varint


class TestDatabaseReader(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.state_db_path = os.path.join(self.temp_dir.name, "state.sqlite")
        self.conv_dir = os.path.join(self.temp_dir.name, "conversations")
        os.makedirs(self.conv_dir, exist_ok=True)

        # Create state.sqlite
        conn = sqlite3.connect(self.state_db_path)
        c = conn.cursor()
        c.execute("""
            CREATE TABLE projection_threads (
                thread_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                title TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                archived_at TEXT
            )
        """)
        c.execute("""
            CREATE TABLE provider_session_runtime (
                thread_id TEXT PRIMARY KEY,
                provider_name TEXT NOT NULL,
                adapter_key TEXT NOT NULL,
                status TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                resume_cursor_json TEXT
            )
        """)

        # Insert 2 threads: one running, one stopped
        c.execute("""
            INSERT INTO projection_threads (thread_id, project_id, title, updated_at)
            VALUES 
                ('thread-1', 'proj-1', 'Active Feature Work', '2026-10-10T12:00:00Z'),
                ('thread-2', 'proj-1', 'Past Thread', '2026-10-10T11:00:00Z')
        """)
        c.execute("""
            INSERT INTO provider_session_runtime (thread_id, provider_name, adapter_key, status, last_seen_at, resume_cursor_json)
            VALUES
                ('thread-1', 'antigravity', 'antigravity-acp', 'running', '2026-10-10T12:00:00Z', '{"sessionId":"session-1"}'),
                ('thread-2', 'antigravity', 'antigravity-acp', 'stopped', '2026-10-10T11:00:00Z', '{"sessionId":"session-2"}')
        """)
        conn.commit()
        conn.close()

        # Create conversation DB for session-1
        self._create_conv_db("session-1", cached=40000, uncached=5000, completion=1000)

    def _create_conv_db(self, session_id: str, cached: int, uncached: int, completion: int):
        db_path = os.path.join(self.conv_dir, f"{session_id}.db")
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER DEFAULT 0)")

        # Create protobuf payload
        submsg = bytearray()
        submsg.extend(encode_varint((2 << 3) | 0))
        submsg.extend(encode_varint(uncached))
        submsg.extend(encode_varint((3 << 3) | 0))
        submsg.extend(encode_varint(completion))
        submsg.extend(encode_varint((5 << 3) | 0))
        submsg.extend(encode_varint(cached))

        f1 = bytearray()
        f1.extend(encode_varint((4 << 3) | 2))
        f1.extend(encode_varint(len(submsg)))
        f1.extend(submsg)

        root = bytearray()
        root.extend(encode_varint((1 << 3) | 2))
        root.extend(encode_varint(len(f1)))
        root.extend(f1)

        c.execute("INSERT INTO gen_metadata (idx, data, size) VALUES (1, ?, ?)", (bytes(root), len(root)))
        conn.commit()
        conn.close()

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_fetch_threads_and_tokens(self):
        config = MonitorConfig(
            state_db_path=self.state_db_path,
            conversations_dir_pattern=os.path.join(self.conv_dir, "*.db"),
        )
        reader = T3DatabaseReader(config)
        threads = reader.get_threads()

        self.assertEqual(len(threads), 2)
        
        # Primary thread should be the running one
        t1 = threads[0]
        self.assertEqual(t1.thread_id, "thread-1")
        self.assertEqual(t1.title, "Active Feature Work")
        self.assertEqual(t1.status, "running")
        self.assertEqual(t1.session_id, "session-1")
        self.assertIsNotNone(t1.tokens)
        self.assertEqual(t1.tokens.total_prompt_tokens, 45000)
        self.assertEqual(t1.tokens.cached_tokens, 40000)
        self.assertEqual(t1.tokens.uncached_tokens, 5000)
        self.assertEqual(t1.tokens.completion_tokens, 1000)

        # Second thread has no conversation DB created yet
        t2 = threads[1]
        self.assertEqual(t2.thread_id, "thread-2")
        self.assertEqual(t2.status, "stopped")
        self.assertIsNone(t2.tokens)


if __name__ == "__main__":
    unittest.main()
