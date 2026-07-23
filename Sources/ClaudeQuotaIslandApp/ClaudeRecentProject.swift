import ClaudeQuotaIslandCore
import Foundation

struct ClaudeRecentProject: Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    var source: ClaudeSnapshotSource
    var sessions: [ClaudeSessionSnapshot]

    var updatedAt: Date {
        sessions.first?.updatedAt ?? .distantPast
    }

    var newestSession: ClaudeSessionSnapshot? {
        sessions.first
    }

    static func groups(
        snapshots: [ClaudeSessionSnapshot],
        remoteConfiguration: RemoteClaudeConfiguration
    ) -> [ClaudeRecentProject] {
        let grouped = Dictionary(grouping: snapshots) { snapshot in
            let source = snapshot.resolvedSource
            let path = canonicalProjectPath(
                snapshot,
                remoteConfiguration: remoteConfiguration
            )
            return "\(source.id)::\(path)"
        }
        return grouped.compactMap { id, values in
            guard let first = values.first else { return nil }
            let path = canonicalProjectPath(first, remoteConfiguration: remoteConfiguration)
            let name = URL(fileURLWithPath: path).lastPathComponent
            return ClaudeRecentProject(
                id: id,
                name: name.isEmpty ? path : name,
                path: path,
                source: first.resolvedSource,
                sessions: values.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func projectID(
        for snapshot: ClaudeSessionSnapshot,
        remoteConfiguration: RemoteClaudeConfiguration
    ) -> String {
        let path = canonicalProjectPath(snapshot, remoteConfiguration: remoteConfiguration)
        return "\(snapshot.resolvedSource.id)::\(path)"
    }

    private static func canonicalProjectPath(
        _ snapshot: ClaudeSessionSnapshot,
        remoteConfiguration: RemoteClaudeConfiguration
    ) -> String {
        let value = snapshot.projectDirectory ?? snapshot.workingDirectory ?? "unknown"
        let normalized = URL(fileURLWithPath: value).standardizedFileURL.path
        guard snapshot.resolvedSource.id == remoteConfiguration.sourceID else {
            return normalized
        }
        return remoteConfiguration.projectPaths
            .filter { normalized == $0 || normalized.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
            ?? normalized
    }
}
