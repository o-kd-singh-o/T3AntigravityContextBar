# Handoff: T3 Antigravity Context Bar

## Session Summary & Accomplishments
We implemented, tested, and published **`t3-antigravity-context-bar`**, a real-time macOS Menu Bar monitor and CLI for T3 Code running with the Google Antigravity provider (Gemini models).

- **GitHub Repository:** [https://github.com/o-kd-singh-o/t3-antigravity-context-bar](https://github.com/o-kd-singh-o/t3-antigravity-context-bar)
- **Active Feature PR:** [PR #1: feat(ui): inline recent threads accordion and full-width title wrapping](https://github.com/o-kd-singh-o/t3-antigravity-context-bar/pull/1) *(Open, unmerged for manual review)*
- **Local Workspace:** `/Users/kd/Documents/Coding/context-window-tokens`
- **Current Branch:** `feat/inline-recent-threads-ui`
- **License:** MIT

---

## What Was Implemented

1. **Telemetry & Protobuf Parsing Engine (`t3_monitor/`)**:
   - `proto.py`: Pure-Python zero-dependency Protobuf wire-format parser decoding nested Google Gemini `UsageMetadata` (uncached prompt tokens, cached prompt tokens, completion tokens, thought tokens). Compatible with Python 3.9 through 3.12+ (uses `Union` syntax for macOS default `/usr/bin/python3`).
   - `db.py`: Read-only (`mode=ro`) SQLite query engine accessing `~/.t3/userdata/state.sqlite` and conversation databases (`gen_metadata`).
   - `engine.py`: Calculates context metrics, cache ratios, and health states:
     - 🟢 **Healthy:** `< 100,000` tokens (`#3fb950`)
     - 🟡 **Warning:** `100,000 – 119,999` tokens (`#d29922`)
     - 🔴 **Critical:** `≥ 120,000` tokens (`#f85149`)
   - `formatters/`: SwiftBar format, JSON format, and ANSI terminal color dashboard.

2. **Native macOS Menu Bar App (`macos_app/`)**:
   - Built natively in Swift with AppKit (`LSUIElement = true`).
   - App Bundle: `T3AntigravityContextBar.app` with Retina icon `macos_app/Resources/AppIcon.icns`.
   - Bundled Python backend: `T3AntigravityContextBar.app/Contents/Resources/t3_monitor/` makes the app completely standalone.
   - Colored dot and live status in menu bar (e.g. `● T3: 98.5k (82%)`).
   - **Compact UI Profile**:
     - Narrow width (~220pt) with multi-line word wrapping (`maxLineLength: 26`, up to 3 lines) to display long chat titles cleanly without stretching window width.
     - Squeezed 8-character progress bar: `[██░░░░░░] 98.5k / 120k (82%)`.
     - Concise status badges (`🟢 Context Healthy`, `🟡 Warning: Plan handoff`, `🔴 Critical: Handoff needed`).
     - Removed redundant "Open T3 Code" and threshold legend labels.
   - **Native Smooth Accordion Presentation (`NSPopover`)**:
     - Replaced `NSMenu` dismissal tracking with native macOS `NSPopover` to eliminate window reload/screen flicker on interaction.
     - **Recent Threads Accordion**: Clicking turns the arrow from horizontal `▶` to vertical downwards `▼` and slides the recent threads down using `NSAnimationContext` in the same window.
     - **Context Breakdown Flyouts**: Dedicated context metric dialog boxes for the active thread and individual recent threads display on click/hover.
     - Keyboard shortcuts: `⌘R` (Refresh), `⌘Q` (Quit), and `Esc` (Close).

3. **SwiftBar / xbar Plugin (`plugins/swiftbar/`)**:
   - `plugins/swiftbar/t3_tokens.10s.py` ready to be symlinked to `~/Library/Application Support/SwiftBar/plugins/` via `make install-swiftbar`.

4. **CLI & Live Monitor**:
   - `make cli`: Single snapshot in terminal.
   - `make watch`: Live 5-second updating terminal dashboard.

5. **Test Suite (TDD)**:
   - 11 unit tests in `tests/` covering proto encoding/decoding, SQLite querying, threshold calculations, and formatters (`make test`).

---

## Repository Structure
```
context-window-tokens/
├── Makefile
├── README.md
├── HANDOFF.md
├── LICENSE
├── pyproject.toml
├── macos_app/
│   ├── Resources/
│   │   ├── Info.plist
│   │   └── AppIcon.icns
│   └── Sources/T3ContextBar/
│       ├── Models.swift
│       ├── MonitorService.swift
│       ├── StatusBarController.swift
│       └── main.swift
├── plugins/
│   └── swiftbar/
│       └── t3_tokens.10s.py
├── t3_monitor/
│   ├── __init__.py
│   ├── __main__.py
│   ├── config.py
│   ├── db.py
│   ├── engine.py
│   ├── proto.py
│   └── formatters/
└── tests/
```

---

## Commands to Run and Install

```bash
cd /Users/kd/Documents/Coding/context-window-tokens

# 1. Build and run the macOS Menu Bar app immediately
make run

# 2. Or open directly via macOS 'open' command
open T3AntigravityContextBar.app

# 3. Install permanently to ~/Applications (launchable via Spotlight or Finder)
make install

# 4. Stop the running menu bar app
make stop

# 5. Run terminal dashboard in watch mode
make watch

# 6. Run unit tests
make test
```

---

## Open Tasks & Next Steps

1. **Review and Merge PR #1**:
   - [Pull Request #1](https://github.com/o-kd-singh-o/t3-antigravity-context-bar/pull/1) is open on GitHub awaiting manual merge into `main`.
2. **Optional Future Enhancements**:
   - File-system watcher on `~/.t3/userdata/state.sqlite-wal` via `DispatchSource.makeFileSystemObjectSource` for instant sub-millisecond refresh when active chat writes to SQLite.
