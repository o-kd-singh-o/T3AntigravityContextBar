import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath

        var candidatePaths: [String] = []

        if let envPath = ProcessInfo.processInfo.environment["T3_WORKSPACE_PATH"] {
            candidatePaths.append(envPath)
        }
        if let resPath = Bundle.main.resourcePath {
            candidatePaths.append(resPath)
        }
        candidatePaths.append(currentDir)
        candidatePaths.append(Bundle.main.bundlePath)
        candidatePaths.append((Bundle.main.bundlePath as NSString).deletingLastPathComponent)
        candidatePaths.append(((Bundle.main.bundlePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("../.."))

        var workspacePath = currentDir
        for p in candidatePaths {
            guard !p.isEmpty else { continue }
            let standardized = (p as NSString).standardizingPath
            let check = (standardized as NSString).appendingPathComponent("t3_monitor")
            if fileManager.fileExists(atPath: check) {
                workspacePath = standardized
                break
            }
        }

        let monitorService = MonitorService(workspacePath: workspacePath)
        statusBarController = StatusBarController(monitorService: monitorService)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
