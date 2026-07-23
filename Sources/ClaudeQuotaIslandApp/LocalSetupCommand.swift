import ClaudeQuotaIslandCore
import Foundation

enum LocalSetupCommand {
    static func discoverSessions() -> Int32 {
        do {
            let sessions = try LocalSessionDiscovery.discover()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(sessions))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(
                Data("Local discovery failed: \(error.localizedDescription)\n".utf8)
            )
            return 1
        }
    }

    static func installWrapper() -> Int32 {
        guard let executableURL = Bundle.main.executableURL else {
            FileHandle.standardError.write(Data("Local setup failed: app executable missing.\n".utf8))
            return 1
        }

        do {
            let status = try StatusLineInstaller().install(
                executableURL: executableURL,
                preserveExistingStatusLine: true
            )
            guard status.isHealthy else {
                FileHandle.standardError.write(Data("Local setup did not produce a healthy wrapper.\n".utf8))
                return 1
            }
            print("Local Claude status-line wrapper installed.")
            return 0
        } catch {
            FileHandle.standardError.write(
                Data("Local setup failed: \(error.localizedDescription)\n".utf8)
            )
            return 1
        }
    }
}
