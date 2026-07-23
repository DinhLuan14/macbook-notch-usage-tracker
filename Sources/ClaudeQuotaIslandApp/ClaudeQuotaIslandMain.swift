import ClaudeQuotaIslandCore
import Darwin
import Foundation

@main
enum ClaudeQuotaIslandMain {
    static func main() {
        if CommandLine.arguments.contains("--statusline-ingest") {
            exit(StatusLineCommand.run(mode: .ingestOnly))
        }
        if CommandLine.arguments.contains("--statusline-render") {
            exit(StatusLineCommand.run(mode: .ingestAndRender))
        }
        if CommandLine.arguments.contains("--remote-install")
            || CommandLine.arguments.contains("--remote-uninstall")
            || CommandLine.arguments.contains("--remote-discover") {
            exit(RemoteSetupCommand.run(arguments: CommandLine.arguments))
        }
        if CommandLine.arguments.contains("--local-install-wrapper") {
            exit(LocalSetupCommand.installWrapper())
        }
        if CommandLine.arguments.contains("--local-discover") {
            exit(LocalSetupCommand.discoverSessions())
        }

        MainActor.assumeIsolated {
            ClaudeQuotaIslandApplication.run()
        }
    }
}
