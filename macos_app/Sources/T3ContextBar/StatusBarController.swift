import AppKit
import Foundation

// MARK: - Separator View

class SeparatorView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        bounds.insetBy(dx: 8, dy: 0).fill()
    }
}

// MARK: - Menu Item Row View

class MenuItemRowView: NSView {
    private var trackingArea: NSTrackingArea?
    var isHighlighted: Bool = false {
        didSet {
            needsDisplay = true
            updateColors()
        }
    }
    var onClick: (() -> Void)?
    let label = NSTextField(labelWithString: "")
    let shortcutLabel = NSTextField(labelWithString: "")
    let chevronLabel = NSTextField(labelWithString: "")
    var customNormalColor: NSColor?

    init(title: String, shortcut: String = "", chevron: String = "", normalColor: NSColor? = nil, font: NSFont = NSFont.systemFont(ofSize: 12)) {
        self.customNormalColor = normalColor
        super.init(frame: .zero)
        setup(title: title, shortcut: shortcut, chevron: chevron, font: font)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(title: String, shortcut: String, chevron: String, font: NSFont) {
        wantsLayer = true
        label.stringValue = title
        label.font = font
        label.textColor = customNormalColor ?? .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        shortcutLabel.stringValue = shortcut
        shortcutLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shortcutLabel)

        chevronLabel.stringValue = chevron
        chevronLabel.font = NSFont.systemFont(ofSize: 12)
        chevronLabel.textColor = .secondaryLabelColor
        chevronLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevronLabel)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -4),

            shortcutLabel.trailingAnchor.constraint(equalTo: chevronLabel.leadingAnchor, constant: -2),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevronLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    func updateTitle(_ newTitle: String) {
        label.stringValue = newTitle
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let cornerPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4)
            cornerPath.fill()
        }
    }

    private func updateColors() {
        label.textColor = isHighlighted ? .white : (customNormalColor ?? .labelColor)
        shortcutLabel.textColor = isHighlighted ? .white.withAlphaComponent(0.8) : .secondaryLabelColor
        chevronLabel.textColor = isHighlighted ? .white.withAlphaComponent(0.8) : .secondaryLabelColor
    }
}

// MARK: - Popover Content Controller

class PopoverContentController: NSViewController {
    var isRecentThreadsExpanded: Bool = false
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onBreakdownClick: ((NSView) -> Void)?
    var onThreadDetailClick: ((ThreadDTO, NSView) -> Void)?

    private let stackView = NSStackView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let recLabel = NSTextField(labelWithString: "")
    private var breakdownRow: MenuItemRowView?
    private var recentHeaderRow: MenuItemRowView?
    private let recentContainer = NSStackView()
    private var otherThreads: [ThreadDTO] = []

    override func loadView() {
        let visualView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 220, height: 180))
        visualView.material = .popover
        visualView.state = .active
        visualView.blendingMode = .behindWindow

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 3
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        visualView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: visualView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: visualView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: visualView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualView.bottomAnchor),
            visualView.widthAnchor.constraint(equalToConstant: 220)
        ])

        self.view = visualView
    }

    func updateData(snapshot: SnapshotDTO) {
        // Clear previous arranged subviews
        stackView.arrangedSubviews.forEach { v in
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        // Active thread header
        if let active = snapshot.active_thread, let m = active.metrics {
            // maxLineLength: 26, maxLines: 3 keeps the extension width compact while showing long titles
            let wrappedTitle = wrapTitle(active.title, maxLineLength: 26, maxLines: 3)
            titleLabel.stringValue = wrappedTitle
            titleLabel.font = NSFont.boldSystemFont(ofSize: 12)
            titleLabel.textColor = .labelColor
            titleLabel.maximumNumberOfLines = 3
            titleLabel.lineBreakMode = .byWordWrapping

            let titleContainer = NSView()
            titleContainer.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleContainer.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 10),
                titleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -10),
                titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor),
                titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor)
            ])
            stackView.addArrangedSubview(titleContainer)

            let progressText = "\(renderProgressBar(pct: m.percentage, width: 8)) \(m.formatted_tokens) / \(formatK(snapshot.config.max_threshold)) (\(Int(m.percentage.rounded()))%)"
            progressLabel.stringValue = progressText
            progressLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            progressLabel.textColor = .secondaryLabelColor

            let progressContainer = NSView()
            progressContainer.translatesAutoresizingMaskIntoConstraints = false
            progressLabel.translatesAutoresizingMaskIntoConstraints = false
            progressContainer.addSubview(progressLabel)
            NSLayoutConstraint.activate([
                progressLabel.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor, constant: 10),
                progressLabel.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor, constant: -10),
                progressLabel.topAnchor.constraint(equalTo: progressContainer.topAnchor),
                progressLabel.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor)
            ])
            stackView.addArrangedSubview(progressContainer)

            let recText: String
            switch m.status_level {
            case "critical":
                recText = "🔴 Critical: Handoff needed"
            case "warning":
                recText = "🟡 Warning: Plan handoff"
            default:
                recText = "🟢 Context Healthy"
            }
            recLabel.stringValue = recText
            recLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            recLabel.textColor = colorFromHex(m.color_hex)

            let recContainer = NSView()
            recContainer.translatesAutoresizingMaskIntoConstraints = false
            recLabel.translatesAutoresizingMaskIntoConstraints = false
            recContainer.addSubview(recLabel)
            NSLayoutConstraint.activate([
                recLabel.leadingAnchor.constraint(equalTo: recContainer.leadingAnchor, constant: 10),
                recLabel.trailingAnchor.constraint(equalTo: recContainer.trailingAnchor, constant: -10),
                recLabel.topAnchor.constraint(equalTo: recContainer.topAnchor),
                recLabel.bottomAnchor.constraint(equalTo: recContainer.bottomAnchor)
            ])
            stackView.addArrangedSubview(recContainer)

            stackView.addArrangedSubview(SeparatorView())

            // Context Breakdown row
            let breakdown = MenuItemRowView(title: "Context Breakdown", chevron: "›")
            breakdown.onClick = { [weak self, weak breakdown] in
                guard let self = self, let breakdown = breakdown else { return }
                self.onBreakdownClick?(breakdown)
            }
            self.breakdownRow = breakdown
            stackView.addArrangedSubview(breakdown)

            stackView.addArrangedSubview(SeparatorView())
        }

        // Recent threads (accordion with animated arrow turning from ▶ to ▼)
        otherThreads = snapshot.threads.filter { t in
            snapshot.active_thread?.thread_id != t.thread_id
        }

        if !otherThreads.isEmpty {
            let arrow = isRecentThreadsExpanded ? "▼" : "▶"
            let headerTitle = "\(arrow) Recent Threads (\(otherThreads.count))"
            let recentHeader = MenuItemRowView(title: headerTitle, font: NSFont.systemFont(ofSize: 12, weight: .medium))
            recentHeader.onClick = { [weak self] in
                self?.toggleRecentThreads()
            }
            self.recentHeaderRow = recentHeader
            stackView.addArrangedSubview(recentHeader)

            // Setup container for recent threads
            recentContainer.arrangedSubviews.forEach { v in
                recentContainer.removeArrangedSubview(v)
                v.removeFromSuperview()
            }
            recentContainer.orientation = .vertical
            recentContainer.alignment = .width
            recentContainer.spacing = 1
            recentContainer.translatesAutoresizingMaskIntoConstraints = false
            recentContainer.isHidden = !isRecentThreadsExpanded

            for t in otherThreads {
                let tokenDesc = t.metrics != nil ? " (\(t.metrics!.formatted_tokens))" : ""
                let titleTruncated = t.title.count > 16 ? String(t.title.prefix(15)) + "..." : t.title
                let itemTitle = "  ● \(titleTruncated)\(tokenDesc)"
                let dotColor = t.metrics != nil ? colorFromHex(t.metrics!.color_hex) : NSColor.secondaryLabelColor
                let threadRow = MenuItemRowView(title: itemTitle, chevron: "›", normalColor: dotColor, font: NSFont.systemFont(ofSize: 11))
                threadRow.onClick = { [weak self, weak threadRow] in
                    guard let self = self, let threadRow = threadRow else { return }
                    self.onThreadDetailClick?(t, threadRow)
                }
                recentContainer.addArrangedSubview(threadRow)
            }

            stackView.addArrangedSubview(recentContainer)
            stackView.addArrangedSubview(SeparatorView())
        }

        // Action rows
        let refreshRow = MenuItemRowView(title: "Refresh Now", shortcut: "⌘R")
        refreshRow.onClick = { [weak self] in
            self?.onRefresh?()
        }
        stackView.addArrangedSubview(refreshRow)

        let quitRow = MenuItemRowView(title: "Quit Context Bar", shortcut: "⌘Q")
        quitRow.onClick = { [weak self] in
            self?.onQuit?()
        }
        stackView.addArrangedSubview(quitRow)

        self.view.layoutSubtreeIfNeeded()
    }

    private func toggleRecentThreads() {
        isRecentThreadsExpanded.toggle()
        let arrow = isRecentThreadsExpanded ? "▼" : "▶"
        recentHeaderRow?.updateTitle("\(arrow) Recent Threads (\(otherThreads.count))")

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            recentContainer.isHidden = !isRecentThreadsExpanded
            self.view.layoutSubtreeIfNeeded()
        })
    }

    private func wrapTitle(_ text: String, maxLineLength: Int = 26, maxLines: Int = 3) -> String {
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

// MARK: - Status Bar Controller

class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverContent: PopoverContentController!
    private var monitorService: MonitorService
    private var timer: Timer?
    private var currentSnapshot: SnapshotDTO?
    private var eventMonitor: Any?

    init(monitorService: MonitorService) {
        self.monitorService = monitorService
        super.init()
        setupStatusItem()
        setupPopover()
        startTimer()
        refresh()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "T3: ..."
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        popoverContent = PopoverContentController()
        popoverContent.onRefresh = { [weak self] in
            self?.refresh()
        }
        popoverContent.onQuit = { [weak self] in
            self?.quitApp()
        }
        popoverContent.onBreakdownClick = { [weak self] anchorView in
            self?.showBreakdownMenu(anchorView: anchorView)
        }
        popoverContent.onThreadDetailClick = { [weak self] thread, anchorView in
            self?.showThreadDetailMenu(thread: thread, anchorView: anchorView)
        }

        popover.contentViewController = popoverContent
    }

    private func startTimer() {
        timer?.invalidate()
        let interval: TimeInterval = 10.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseUp {
            // Right-click quick context menu
            let quickMenu = NSMenu()
            quickMenu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r"))
            quickMenu.addItem(NSMenuItem.separator())
            quickMenu.addItem(NSMenuItem(title: "Quit Context Bar", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = quickMenu
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popoverContent.view.window?.makeKey()
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

        popoverContent.updateData(snapshot: snapshot)
    }

    private func updateError(error: Error) {
        if let button = statusItem.button {
            button.title = "⚠️ T3: Error"
        }
    }

    private func showBreakdownMenu(anchorView: NSView) {
        guard let snapshot = currentSnapshot, let m = snapshot.active_thread?.metrics else { return }
        let menu = NSMenu()

        let addSubItem = { (label: String, value: String) in
            let item = NSMenuItem(title: "\(label): \(value)", action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(
                string: "\(label): \(value)",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
            )
            menu.addItem(item)
        }

        addSubItem("Total Context", "\(formatNumber(m.total_prompt_tokens)) tokens")
        addSubItem("Cached Context", "\(formatNumber(m.cached_tokens)) tokens (\(String(format: "%.1f", m.cache_ratio))%)")
        addSubItem("New Input", "\(formatNumber(m.uncached_tokens)) tokens")
        addSubItem("Last Output", "\(formatNumber(m.completion_tokens)) tokens")
        if m.thought_tokens > 0 {
            addSubItem("Reasoning", "\(formatNumber(m.thought_tokens)) tokens")
        }
        addSubItem("Remaining", "\(formatNumber(m.remaining_tokens)) tokens")

        menu.popUp(positioning: nil, at: NSPoint(x: anchorView.bounds.maxX + 4, y: anchorView.bounds.midY), in: anchorView)
    }

    private func showThreadDetailMenu(thread: ThreadDTO, anchorView: NSView) {
        let menu = NSMenu()
        let addDetail = { (text: String) in
            let detailItem = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            detailItem.attributedTitle = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
            )
            menu.addItem(detailItem)
        }

        addDetail("Title: \(thread.title)")
        addDetail("Thread ID: \(thread.thread_id)")
        addDetail("Status: \(thread.status)")
        if let tm = thread.metrics {
            addDetail("Prompt: \(formatNumber(tm.total_prompt_tokens)) tokens (\(Int(tm.percentage.rounded()))%)")
            addDetail("Cached: \(formatNumber(tm.cached_tokens)) tokens (\(String(format: "%.1f", tm.cache_ratio))%)")
        }
        addDetail("Updated: \(thread.updated_at)")

        menu.popUp(positioning: nil, at: NSPoint(x: anchorView.bounds.maxX + 4, y: anchorView.bounds.midY), in: anchorView)
    }

    func popoverDidShow(_ notification: Notification) {
        startEventMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "r" {
                    self?.refresh()
                    return nil
                }
                if event.charactersIgnoringModifiers == "q" {
                    self?.quitApp()
                    return nil
                }
            }
            if event.keyCode == 53 { // ESC
                self?.popover.performClose(nil)
                return nil
            }
            return event
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
