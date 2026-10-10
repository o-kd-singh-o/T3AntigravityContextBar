#!/usr/bin/env python3
# <xbar.title>T3 Antigravity Context Bar</xbar.title>
# <xbar.version>v1.0.0</xbar.version>
# <xbar.author>T3 Antigravity Context Bar Contributors</xbar.author>
# <xbar.author.github>antigravity</xbar.author.github>
# <xbar.desc>Live context-window token monitor for T3 Code with Antigravity / Gemini</xbar.desc>
# <xbar.image>https://raw.githubusercontent.com/google/material-design-icons/master/png/action/speed/materialicons/24dp/1x/baseline_speed_black_24dp.png</xbar.image>
# <xbar.dependencies>python3</xbar.dependencies>

import os
import sys

# Ensure this workspace's t3_monitor package is importable
workspace_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if workspace_root not in sys.path:
    sys.path.insert(0, workspace_root)

try:
    from t3_monitor.config import MonitorConfig
    from t3_monitor.engine import get_monitor_snapshot
    from t3_monitor.formatters.swiftbar import format_swiftbar

    config = MonitorConfig.from_env()
    snapshot = get_monitor_snapshot(config)
    print(format_swiftbar(snapshot))
except Exception as e:
    print(f"⚠️ T3: Error | color=#f85149")
    print("---")
    print(f"Error: {e}")
