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
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        attrTitle.append(NSAttributedString(string: snapshot.menu_bar_title, attributes: textAttr))

        button.attributedTitle = attrTitle

        // Rebuild Menu
        let menu = NSMenu()

        // Active thread header
        if let active = snapshot.active_thread, let m = active.metrics {
            let titleItem = NSMenuItem(title: "Active: \(active.title)", action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(
                string: "Active: \(active.title)",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
            )
            menu.addItem(titleItem)

            // Progress bar item
            let progressText = "\(renderProgressBar(pct: m.percentage)) \(m.formatted_tokens) / \(formatK(snapshot.config.max_threshold)) (\(Int(m.percentage.rounded()))%)"
            let progressItem = NSMenuItem(title: progressText, action: nil, keyEquivalent: "")
            progressItem.attributedTitle = NSAttributedString(
                string: progressText,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
            )
            menu.addItem(progressItem)

            // Recommendation badge
            let recIcon = m.status_level == "critical" ? "🔴" : (m.status_level == "warning" ? "🟡" : "🟢")
            let recItem = NSMenuItem(title: "\(recIcon) \(m.recommendation)", action: nil, keyEquivalent: "")
            recItem.attributedTitle = NSAttributedString(
                string: "\(recIcon) \(m.recommendation)",
                attributes: [.foregroundColor: colorFromHex(m.color_hex)]
            )
            menu.addItem(recItem)

            menu.addItem(NSMenuItem.separator())

            // Breakdown submenu
            let breakdownItem = NSMenuItem(title: "Context Breakdown", action: nil, keyEquivalent: "")
            let subMenu = NSMenu()
            
            let addSubItem = { (label: String, value: String) in
                let item = NSMenuItem(title: "\(label): \(value)", action: nil, keyEquivalent: "")
                item.attributedTitle = NSAttributedString(
                    string: "\(label): \(value)",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
                )
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
        }

        // Recent threads collapsed under a dropdown menu
        let otherThreads = snapshot.threads.filter { t in
            snapshot.active_thread?.thread_id != t.thread_id
        }

        if !otherThreads.isEmpty {
            let recentThreadsTitle = "Recent Threads (\(otherThreads.count)) ▾"
            let recentThreadsItem = NSMenuItem(title: recentThreadsTitle, action: nil, keyEquivalent: "")
            recentThreadsItem.attributedTitle = NSAttributedString(
                string: recentThreadsTitle,
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
            )

            let recentSubMenu = NSMenu()

            for t in otherThreads {
                let tokenDesc = t.metrics != nil ? "(\(t.metrics!.formatted_tokens))" : ""
                let titleTruncated = t.title.count > 35 ? String(t.title.prefix(32)) + "..." : t.title
                let itemTitle = "● \(titleTruncated) \(tokenDesc) [\(t.status)]"
                let threadItem = NSMenuItem(title: itemTitle, action: nil, keyEquivalent: "")
                
                let dotColor = t.metrics != nil ? colorFromHex(t.metrics!.color_hex) : NSColor.secondaryLabelColor
                threadItem.attributedTitle = NSAttributedString(
                    string: itemTitle,
                    attributes: [.foregroundColor: dotColor, .font: NSFont.systemFont(ofSize: 11)]
                )

                // Submenu for thread details
                let tSubMenu = NSMenu()
                let addDetail = { (text: String) in
                    let detailItem = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                    detailItem.attributedTitle = NSAttributedString(
                        string: text,
                        attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
                    )
                    tSubMenu.addItem(detailItem)
                }
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

        // Config & Controls
        let configDesc = "Thresholds: Warn \(formatK(snapshot.config.warn_threshold)), Max \(formatK(snapshot.config.max_threshold))"
        let configItem = NSMenuItem(title: configDesc, action: nil, keyEquivalent: "")
        configItem.attributedTitle = NSAttributedString(
            string: configDesc,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 10)]
        )
        menu.addItem(configItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openT3Item = NSMenuItem(title: "Open T3 Code", action: #selector(openT3Code), keyEquivalent: "o")
        openT3Item.target = self
        menu.addItem(openT3Item)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit T3 Antigravity Context Bar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateError(error: Error) {
        if let button = statusItem.button {
            button.title = "⚠️ T3: Error"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Error: \(error.localizedDescription)", action: nil, keyEquivalent: ""))
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
        menu.addItem(NSMenuItem(title: "Checking T3 context tokens...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func openT3Code() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "T3 Code"]
        try? process.run()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func renderProgressBar(pct: Double, width: Int = 14) -> String {
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
            return NSColor.textColor
        }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
