import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath

        var candidatePaths = [
            currentDir,
            Bundle.main.bundlePath,
            (Bundle.main.bundlePath as NSString).deletingLastPathComponent,
            ((Bundle.main.bundlePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("../..")
        ]

        if let envPath = ProcessInfo.processInfo.environment["T3_WORKSPACE_PATH"] {
            candidatePaths.insert(envPath, at: 0)
        }

        var workspacePath = currentDir
        for p in candidatePaths {
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
