import Foundation

public enum StatusLineCommandMode: Sendable {
    case ingestOnly
    case ingestAndRender
}

public enum StatusLineCommand {
    public static func process(
        _ data: Data,
        mode: StatusLineCommandMode,
        store: SnapshotStore = SnapshotStore(),
        now: Date = .now,
        source: ClaudeSnapshotSource = .local
    ) throws -> String? {
        let payload = try JSONDecoder().decode(ClaudeStatusLinePayload.self, from: data)
        _ = try store.ingest(payload, at: now, source: source)
        guard mode == .ingestAndRender else { return nil }
        return render(payload)
    }

    public static func render(_ payload: ClaudeStatusLinePayload) -> String {
        let model = payload.model?.displayName ?? "Claude"
        let percentage = payload.contextWindow?.usedPercentage.map { Int($0.rounded()) } ?? 0
        return "[\(model)] \(percentage)% context"
    }

    public static func run(mode: StatusLineCommandMode) -> Int32 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        do {
            if let output = try process(data, mode: mode) {
                FileHandle.standardOutput.write(Data("\(output)\n".utf8))
            }
            return 0
        } catch {
            if ProcessInfo.processInfo.environment["CQI_DEBUG_STATUSLINE"] == "1" {
                FileHandle.standardError.write(Data("ClaudeQuotaIsland: \(error)\n".utf8))
            }
            return 0
        }
    }
}
