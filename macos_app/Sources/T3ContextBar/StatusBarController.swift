import AppKit
import Foundation

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var monitorService: MonitorService
    private var timer: Timer?
    private var currentSnapshot: SnapshotDTO?

    init(monitorService: MonitorService) {
        self.monitorService = monitorService
        super.init()
        setupStatusItem()
        startTimer()
        refresh()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "T3: ..."
        }
        buildLoadingMenu()
    }

    private func startTimer() {
        timer?.invalidate()
        let interval: TimeInterval = 10.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc func refresh() {
        monitorService.fetchSnapshot { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let snapshot):
                self.currentSnapshot = snapshot
                self.updateUI(snapshot: snapshot)
            case .failure(let error):
                self.updateError(error: error)
            }
        }
    }

    private func updateUI(snapshot: SnapshotDTO) {
        guard let button = statusItem.button else { return }

        // Setup colored attributed string for Menu Bar: "● T3: 75.3k (63%)"
        let statusColor = colorFromHex(snapshot.overall_color_hex)
        let attrTitle = NSMutableAttributedString()
        
        let dotAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: statusColor,
            .font: NSFont.systemFont(ofSize: 12, weight: .bold)
        ]
        attrTitle.append(NSAttributedString(string: "● ", attributes: dotAttr))

        let textAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        attrTitle.append(NSAttributedString(string: snapshot.menu_bar_title, attributes: textAttr))

        button.attributedTitle = attrTitle

        // Rebuild Menu with autoenablesItems disabled so informative items stay enabled & full opacity
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Active thread header
        if let active = snapshot.active_thread, let m = active.metrics {
            let wrappedTitle = wrapTitle(active.title, maxLineLength: 26, maxLines: 2)
            let titleItem = NSMenuItem(title: wrappedTitle, action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(
                string: wrappedTitle,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            titleItem.isEnabled = true
            menu.addItem(titleItem)

            // Progress bar item (compact single line, white high-contrast text)
            let progressText = "\(renderProgressBar(pct: m.percentage, width: 8)) \(m.formatted_tokens) / \(formatK(snapshot.config.max_threshold)) (\(Int(m.percentage.rounded()))%)"
            let progressItem = NSMenuItem(title: progressText, action: nil, keyEquivalent: "")
            progressItem.attributedTitle = NSAttributedString(
                string: progressText,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            progressItem.isEnabled = true
            menu.addItem(progressItem)

            // Recommendation badge (compact)
            let recText: String
            switch m.status_level {
            case "critical":
                recText = "🔴 Critical: Handoff needed"
            case "warning":
                recText = "🟡 Warning: Plan handoff"
            default:
                recText = "🟢 Context Healthy"
            }
            let recItem = NSMenuItem(title: recText, action: nil, keyEquivalent: "")
            recItem.attributedTitle = NSAttributedString(
                string: recText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            recItem.isEnabled = true
            menu.addItem(recItem)

            menu.addItem(NSMenuItem.separator())

            // Breakdown submenu
            let breakdownItem = NSMenuItem(title: "Context Breakdown", action: nil, keyEquivalent: "")
            breakdownItem.attributedTitle = NSAttributedString(
                string: "Context Breakdown",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            breakdownItem.isEnabled = true

            let subMenu = NSMenu()
            subMenu.autoenablesItems = false
            
            let addSubItem = { (label: String, value: String) in
                let fullText = "\(label): \(value)"
                let item = NSMenuItem(title: fullText, action: nil, keyEquivalent: "")
                item.attributedTitle = NSAttributedString(
                    string: fullText,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: NSColor.labelColor
                    ]
                )
                item.isEnabled = true
                subMenu.addItem(item)
            }

            addSubItem("Total Context", "\(formatNumber(m.total_prompt_tokens)) tokens")
            addSubItem("Cached Context", "\(formatNumber(m.cached_tokens)) tokens (\(String(format: "%.1f", m.cache_ratio))%)")
            addSubItem("New Input", "\(formatNumber(m.uncached_tokens)) tokens")
            addSubItem("Last Output", "\(formatNumber(m.completion_tokens)) tokens")
            if m.thought_tokens > 0 {
                addSubItem("Reasoning", "\(formatNumber(m.thought_tokens)) tokens")
            }
            addSubItem("Remaining", "\(formatNumber(m.remaining_tokens)) tokens")
            breakdownItem.submenu = subMenu
            menu.addItem(breakdownItem)

            menu.addItem(NSMenuItem.separator())
        } else if let active = snapshot.active_thread {
            let wrappedTitle = wrapTitle(active.title, maxLineLength: 26, maxLines: 2)
            let titleItem = NSMenuItem(title: wrappedTitle, action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(
                string: wrappedTitle,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            titleItem.isEnabled = true
            menu.addItem(titleItem)

            let noMetricsItem = NSMenuItem(title: "No token telemetry recorded yet", action: nil, keyEquivalent: "")
            noMetricsItem.attributedTitle = NSAttributedString(
                string: "No token telemetry recorded yet",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            noMetricsItem.isEnabled = true
            menu.addItem(noMetricsItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Recent threads collapsed under a dropdown menu
        let otherThreads = snapshot.threads.filter { t in
            snapshot.active_thread?.thread_id != t.thread_id
        }

        if !otherThreads.isEmpty {
            let recentThreadsTitle = "Recent Threads (\(otherThreads.count))"
            let recentThreadsItem = NSMenuItem(title: recentThreadsTitle, action: nil, keyEquivalent: "")
            recentThreadsItem.attributedTitle = NSAttributedString(
                string: recentThreadsTitle,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            recentThreadsItem.isEnabled = true

            let recentSubMenu = NSMenu()
            recentSubMenu.autoenablesItems = false

            for t in otherThreads {
                let tokenDesc = t.metrics != nil ? " (\(t.metrics!.formatted_tokens))" : ""
                let titleTruncated = t.title.count > 20 ? String(t.title.prefix(18)) + "..." : t.title
                let threadItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                
                let dotColor = t.metrics != nil ? colorFromHex(t.metrics!.color_hex) : NSColor.secondaryLabelColor
                let attrTitle = NSMutableAttributedString()
                attrTitle.append(NSAttributedString(
                    string: "● ",
                    attributes: [.foregroundColor: dotColor, .font: NSFont.systemFont(ofSize: 11)]
                ))
                attrTitle.append(NSAttributedString(
                    string: "\(titleTruncated)\(tokenDesc)",
                    attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 11)]
                ))
                threadItem.attributedTitle = attrTitle
                threadItem.isEnabled = true

                // Submenu for thread details
                let tSubMenu = NSMenu()
                tSubMenu.autoenablesItems = false
                let addDetail = { (text: String) in
                    let detailItem = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                    detailItem.attributedTitle = NSAttributedString(
                        string: text,
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                    detailItem.isEnabled = true
                    tSubMenu.addItem(detailItem)
                }
                addDetail("Title: \(t.title)")
                addDetail("Thread ID: \(t.thread_id)")
                addDetail("Status: \(t.status)")
                if let tm = t.metrics {
                    addDetail("Prompt: \(formatNumber(tm.total_prompt_tokens)) tokens (\(Int(tm.percentage.rounded()))%)")
                    addDetail("Cached: \(formatNumber(tm.cached_tokens)) tokens (\(String(format: "%.1f", tm.cache_ratio))%)")
                }
                addDetail("Updated: \(t.updated_at)")
                threadItem.submenu = tSubMenu
                recentSubMenu.addItem(threadItem)
            }

            recentThreadsItem.submenu = recentSubMenu
            menu.addItem(recentThreadsItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Controls
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit Context Bar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateError(error: Error) {
        if let button = statusItem.button {
            button.title = "⚠️ T3: Error"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let errorItem = NSMenuItem(title: "Error: \(error.localizedDescription)", action: nil, keyEquivalent: "")
        errorItem.attributedTitle = NSAttributedString(
            string: "Error: \(error.localizedDescription)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
        errorItem.isEnabled = true
        menu.addItem(errorItem)
        menu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(title: "Retry Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func buildLoadingMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let loadingItem = NSMenuItem(title: "Checking T3 tokens...", action: nil, keyEquivalent: "")
        loadingItem.attributedTitle = NSAttributedString(
            string: "Checking T3 tokens...",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
        loadingItem.isEnabled = true
        menu.addItem(loadingItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func wrapTitle(_ text: String, maxLineLength: Int = 26, maxLines: Int = 2) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return text }

        var lines: [String] = []
        var currentLine = ""
        var wordIdx = 0

        while wordIdx < words.count {
            let word = words[wordIdx]
            if lines.count == maxLines - 1 {
                if currentLine.isEmpty {
                    currentLine = word
                } else if currentLine.count + 1 + word.count <= maxLineLength - 3 {
                    currentLine += " " + word
                } else {
                    currentLine += "..."
                    lines.append(currentLine)
                    currentLine = ""
                    break
                }
            } else {
                if currentLine.isEmpty {
                    currentLine = word
                } else if currentLine.count + 1 + word.count <= maxLineLength {
                    currentLine += " " + word
                } else {
                    lines.append(currentLine)
                    currentLine = word
                }
            }
            wordIdx += 1
        }

        if !currentLine.isEmpty && lines.count < maxLines {
            if wordIdx < words.count && !currentLine.hasSuffix("...") {
                currentLine += "..."
            }
            lines.append(currentLine)
        }

        return lines.joined(separator: "\n")
    }

    private func renderProgressBar(pct: Double, width: Int = 8) -> String {
        let clamped = max(0.0, min(100.0, pct))
        let filled = Int((clamped / 100.0 * Double(width)).rounded())
        let empty = max(0, width - filled)
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]"
    }

    private func formatK(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            if count % 1_000 == 0 {
                return "\(count / 1_000)k"
            }
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }

    private func colorFromHex(_ hex: String) -> NSColor {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        guard cleanHex.count == 6, let rgb = UInt64(cleanHex, radix: 16) else {
            return NSColor.systemGreen
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
