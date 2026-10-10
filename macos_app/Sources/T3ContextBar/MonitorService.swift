import Foundation

class MonitorService {
    private let workspacePath: String

    init(workspacePath: String) {
        self.workspacePath = workspacePath
    }

    func fetchSnapshot(completion: @escaping (Result<SnapshotDTO, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-m", "t3_monitor", "--format", "json"]
            process.currentDirectoryURL = URL(fileURLWithPath: self.workspacePath)

            var env = ProcessInfo.processInfo.environment
            let existingPythonPath = env["PYTHONPATH"] ?? ""
            env["PYTHONPATH"] = existingPythonPath.isEmpty ? self.workspacePath : "\(self.workspacePath):\(existingPythonPath)"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if data.isEmpty {
                    throw NSError(domain: "T3TokenBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "No output received from monitor engine"])
                }

                let decoder = JSONDecoder()
                let snapshot = try decoder.decode(SnapshotDTO.self, from: data)
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
