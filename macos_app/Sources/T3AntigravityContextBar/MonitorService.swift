import Foundation

class MonitorService {
    private let workspacePath: String

    init(workspacePath: String) {
        self.workspacePath = workspacePath
    }

    private func findPythonExecutable() -> (url: URL, argsPrefix: [String]) {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let envPython = ProcessInfo.processInfo.environment["PYTHON"], !envPython.isEmpty {
            candidates.append(envPython)
        }

        candidates.append(contentsOf: [
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3"
        ])

        for path in candidates {
            if fileManager.isExecutableFile(atPath: path) {
                return (URL(fileURLWithPath: path), [])
            }
        }

        return (URL(fileURLWithPath: "/usr/bin/env"), ["python3"])
    }

    func fetchSnapshot(completion: @escaping (Result<SnapshotDTO, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let (execUrl, argsPrefix) = self.findPythonExecutable()
            process.executableURL = execUrl

            var fullArgs = argsPrefix
            fullArgs.append(contentsOf: ["-m", "t3_monitor", "--format", "json"])
            process.arguments = fullArgs
            process.currentDirectoryURL = URL(fileURLWithPath: self.workspacePath)

            var env = ProcessInfo.processInfo.environment
            let existingPythonPath = env["PYTHONPATH"] ?? ""
            env["PYTHONPATH"] = existingPythonPath.isEmpty ? self.workspacePath : "\(self.workspacePath):\(existingPythonPath)"

            let standardPaths = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
            let existingPath = env["PATH"] ?? ""
            env["PATH"] = existingPath.isEmpty ? standardPaths : "\(existingPath):\(standardPaths)"

            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if outData.isEmpty {
                    let msg = errString.isEmpty ? "No output received from monitor engine" : errString
                    throw NSError(domain: "T3TokenBar", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
                }

                let decoder = JSONDecoder()
                let snapshot = try decoder.decode(SnapshotDTO.self, from: outData)
                DispatchQueue.main.async {
                    completion(.success(snapshot))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
