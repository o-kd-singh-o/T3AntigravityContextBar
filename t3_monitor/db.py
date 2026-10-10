"""Read-only SQLite telemetry reader for T3 Code and Antigravity databases."""

import glob
import json
import os
import sqlite3
from dataclasses import dataclass
from typing import List, Optional

from t3_monitor.config import MonitorConfig
from t3_monitor.proto import TokenUsage, extract_token_usage


@dataclass
class ThreadRecord:
    thread_id: str
    title: str
    status: str
    updated_at: str
    session_id: Optional[str] = None
    tokens: Optional[TokenUsage] = None


class T3DatabaseReader:
    def __init__(self, config: Optional[MonitorConfig] = None):
        self.config = config or MonitorConfig()

    def get_threads(self, limit: Optional[int] = None) -> List[ThreadRecord]:
        """Fetch active threads with their latest token usage."""
        if not os.path.exists(self.config.state_db_path):
            return []

        limit = limit or self.config.max_recent_threads
        threads: List[ThreadRecord] = []

        try:
            # Open state.sqlite in read-only mode
            uri = f"file:{os.path.abspath(self.config.state_db_path)}?mode=ro"
            with sqlite3.connect(uri, uri=True, timeout=2.0) as conn:
                cursor = conn.cursor()
                query = """
                    SELECT 
                        t.thread_id,
                        t.title,
                        t.updated_at,
                        COALESCE(r.status, 'stopped') AS status,
                        r.resume_cursor_json
                    FROM projection_threads t
                    LEFT JOIN provider_session_runtime r ON t.thread_id = r.thread_id
                    WHERE t.deleted_at IS NULL AND (t.archived_at IS NULL OR t.archived_at = '')
                    ORDER BY 
                        CASE WHEN r.status = 'running' THEN 0 ELSE 1 END,
                        t.updated_at DESC
                    LIMIT ?;
                """
                rows = cursor.execute(query, (limit,)).fetchall()
        except Exception:
            return []

        for row in rows:
            thread_id, title, updated_at, status, resume_cursor_json = row
            session_id = None
            if resume_cursor_json:
                try:
                    cursor_data = json.loads(resume_cursor_json)
                    session_id = cursor_data.get("sessionId")
                except Exception:
                    session_id = None

            tokens = self._get_token_usage_for_session(session_id) if session_id else None

            threads.append(
                ThreadRecord(
                    thread_id=thread_id,
                    title=title,
                    status=status,
                    updated_at=updated_at,
                    session_id=session_id,
                    tokens=tokens,
                )
            )

        return threads

    def _get_token_usage_for_session(self, session_id: str) -> Optional[TokenUsage]:
        """Locate conversation DB for session_id and extract most recent TokenUsage."""
        db_path = self._find_conversation_db(session_id)
        if not db_path or not os.path.exists(db_path):
            return None

        try:
            uri = f"file:{os.path.abspath(db_path)}?mode=ro"
            with sqlite3.connect(uri, uri=True, timeout=2.0) as conn:
                cursor = conn.cursor()
                # Scan latest gen_metadata rows in reverse order
                rows = cursor.execute(
                    "SELECT idx, data FROM gen_metadata ORDER BY idx DESC LIMIT 15;"
                ).fetchall()
                for _, data in rows:
                    if data:
                        usage = extract_token_usage(data)
                        if usage:
                            return usage
        except Exception:
            return None

        return None

    def _find_conversation_db(self, session_id: str) -> Optional[str]:
        """Find the exact path of the conversation SQLite DB."""
        pattern = self.config.conversations_dir_pattern

        # Case 1: Pattern already includes a glob wildcard
        if "*" in pattern:
            # Check if pattern ends with *.db
            if pattern.endswith("*.db"):
                # Replace *.db with {session_id}.db
                target_pattern = pattern[:-4] + f"{session_id}.db"
            else:
                target_pattern = os.path.join(pattern, f"{session_id}.db")

            matches = glob.glob(target_pattern)
            if matches:
                return matches[0]

        # Case 2: Exact directory path
        exact_path = os.path.join(pattern, f"{session_id}.db")
        if os.path.exists(exact_path):
            return exact_path

        return None
