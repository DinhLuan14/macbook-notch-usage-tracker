import ClaudeQuotaIslandCore
import Foundation

enum LocalSessionDiscovery {
    private struct Candidate {
        var sessionID: String
        var workingDirectory: String?
        var transcriptPath: String
        var modelID: String?
        var totalInputTokens: Int?
        var totalOutputTokens: Int?
        var updatedAt: Date
    }

    static func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = .now
    ) throws -> [ClaudeSessionSnapshot] {
        let root = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let cutoff = now.addingTimeInterval(-AppModel.sessionRetention)
        let projectDirectories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .compactMap { directory -> (Date, URL)? in
            guard let newest = try? transcriptFiles(in: directory, newerThan: cutoff)
                .compactMap({ try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate })
                .max() else {
                return nil
            }
            return (newest, directory)
        }
        .sorted { $0.0 > $1.0 }
        .prefix(24)

        var snapshots: [ClaudeSessionSnapshot] = []
        for (_, directory) in projectDirectories {
            let files = try transcriptFiles(in: directory, newerThan: cutoff)
                .compactMap { url -> (Date, URL)? in
                    guard let date = try? url.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate else {
                        return nil
                    }
                    return (date, url)
                }
                .sorted { $0.0 > $1.0 }
                .prefix(12)

            let candidates = files.map { date, url in
                parseTranscript(url, modifiedAt: date)
            }
            let directories = candidates.compactMap(\.workingDirectory)
            let projectDirectory = commonDirectory(directories)

            for candidate in candidates {
                let resolvedProject = projectDirectory ?? candidate.workingDirectory
                let folderName = resolvedProject.map {
                    URL(fileURLWithPath: $0).lastPathComponent
                } ?? "Project"
                snapshots.append(
                    ClaudeSessionSnapshot(
                        sessionID: candidate.sessionID,
                        sourceID: ClaudeSnapshotSource.local.id,
                        sourceLabel: ClaudeSnapshotSource.local.label,
                        sourceIsRemote: false,
                        sessionName: "\(folderName) · \(candidate.sessionID.prefix(8))",
                        workingDirectory: candidate.workingDirectory,
                        projectDirectory: resolvedProject,
                        transcriptPath: candidate.transcriptPath,
                        modelID: candidate.modelID,
                        modelDisplayName: modelDisplayName(candidate.modelID),
                        totalInputTokens: candidate.totalInputTokens,
                        totalOutputTokens: candidate.totalOutputTokens,
                        updatedAt: candidate.updatedAt
                    )
                )
            }
        }
        return Array(snapshots.sorted { $0.updatedAt > $1.updatedAt }.prefix(200))
    }

    private static func transcriptFiles(in directory: URL, newerThan cutoff: Date) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(
                      forKeys: [.isRegularFileKey, .contentModificationDateKey]
                  ),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else {
                return false
            }
            return date >= cutoff
        }
    }

    private static func parseTranscript(_ url: URL, modifiedAt: Date) -> Candidate {
        var sessionID = url.deletingPathExtension().lastPathComponent
        var workingDirectory: String?
        var modelID: String?
        var totalInputTokens: Int?
        var totalOutputTokens: Int?

        for line in tailLines(url).reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if workingDirectory == nil, let cwd = event["cwd"] as? String {
                workingDirectory = cwd
            }
            if let value = event["sessionId"] as? String {
                sessionID = value
            }
            guard modelID == nil,
                  event["type"] as? String == "assistant",
                  let message = event["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  !model.hasPrefix("<") else {
                continue
            }
            modelID = model
            if let usage = message["usage"] as? [String: Any] {
                let values = [
                    number(usage["input_tokens"]),
                    number(usage["cache_creation_input_tokens"]),
                    number(usage["cache_read_input_tokens"]),
                ].compactMap(\.self)
                if !values.isEmpty {
                    totalInputTokens = values.reduce(0, +)
                }
                totalOutputTokens = number(usage["output_tokens"])
            }
        }

        return Candidate(
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            transcriptPath: url.path,
            modelID: modelID,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            updatedAt: modifiedAt
        )
    }

    private static func tailLines(_ url: URL, maximumBytes: UInt64 = 1_048_576) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > maximumBytes ? end - maximumBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              var text = String(data: data, encoding: .utf8) else {
            return []
        }
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text.removeSubrange(text.startIndex ... newline)
        }
        return text.split(separator: "\n").suffix(1_000).map(String.init)
    }

    private static func commonDirectory(_ paths: [String]) -> String? {
        guard var components = paths.first.map({
            URL(fileURLWithPath: $0).standardizedFileURL.pathComponents
        }) else {
            return nil
        }
        for path in paths.dropFirst() {
            let other = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
            components = Array(
                zip(components, other).prefix { pair in pair.0 == pair.1 }.map(\.0)
            )
            if components.count <= 1 { return paths.first }
        }
        guard !components.isEmpty else { return paths.first }
        return NSString.path(withComponents: components)
    }

    private static func modelDisplayName(_ modelID: String?) -> String? {
        guard let modelID else { return nil }
        let value = modelID.hasPrefix("claude-") ? String(modelID.dropFirst(7)) : modelID
        let parts = value.split(separator: "-")
        guard let family = parts.first else { return "Claude" }
        let versions = parts.dropFirst().filter { Int($0) != nil }.prefix(2)
        let suffix = versions.isEmpty ? "" : " " + versions.joined(separator: ".")
        return family.capitalized + suffix
    }

    private static func number(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
