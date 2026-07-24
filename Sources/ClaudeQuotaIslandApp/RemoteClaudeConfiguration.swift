import ClaudeQuotaIslandCore
import Foundation

struct RemoteClaudeConfiguration: Codable, Equatable, Sendable {
    var label: String
    var host: String
    var user: String
    var port: Int
    var projectPaths: [String]
    var clientID: String
    var isInstalled: Bool

    init(
        label: String = "My Server",
        host: String = "",
        user: String = "",
        port: Int = 22,
        projectPaths: [String] = [],
        clientID: String = UUID().uuidString.lowercased(),
        isInstalled: Bool = false
    ) {
        self.label = label
        self.host = host
        self.user = user
        self.port = port
        self.projectPaths = Self.normalizedProjectPaths(projectPaths)
        self.clientID = clientID
        self.isInstalled = isInstalled
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case host
        case user
        case port
        case projectPaths
        case clientID
        case isInstalled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "My Server"
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        user = try container.decodeIfPresent(String.self, forKey: .user) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        projectPaths = Self.normalizedProjectPaths(
            try container.decodeIfPresent([String].self, forKey: .projectPaths) ?? []
        )
        let storedClientID = try container.decodeIfPresent(String.self, forKey: .clientID)
        let validStoredClientID = storedClientID.flatMap(UUID.init(uuidString:))?
            .uuidString
            .lowercased()
        clientID = validStoredClientID ?? UUID().uuidString.lowercased()
        isInstalled = validStoredClientID == nil
            ? false
            : (try container.decodeIfPresent(Bool.self, forKey: .isInstalled) ?? false)
    }

    var source: ClaudeSnapshotSource {
        ClaudeSnapshotSource(id: sourceID, label: displayName, isRemote: true)
    }

    var sourceID: String {
        "ssh-primary"
    }

    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if isValid { return "\(user)@\(host)" }
        return "SSH Server"
    }

    var target: String {
        "\(user)@\(host)"
    }

    var isValid: Bool {
        Self.isSafeSSHComponent(
            host,
            allowed: CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: ".:_-%[]")
            )
        )
            && Self.isSafeSSHComponent(
                user,
                allowed: CharacterSet.alphanumerics.union(
                    CharacterSet(charactersIn: "._-")
                )
            )
            && (1 ... 65_535).contains(port)
    }

    var remoteSocketDirectory: String {
        "/tmp/claude-quota-island-\(String(sanitized(user).prefix(32)))"
    }

    var remoteSocketPath: String {
        "\(remoteSocketDirectory)/\(String(sanitized(clientID).prefix(32))).sock"
    }

    static var localSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ClaudeQuotaIsland", isDirectory: true)
            .appendingPathComponent("ssh-relay.sock")
            .path
    }

    static func normalizedProjectPath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              trimmed.utf8.count <= 4_096,
              !trimmed.contains(where: \.isNewline),
              !trimmed.contains("\0") else {
            return nil
        }
        let normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        return normalized == "/" ? nil : normalized
    }

    static func normalizedProjectPaths(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(normalizedProjectPath).filter { seen.insert($0).inserted }
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let normalized = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(normalized).trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }

    private static func isSafeSSHComponent(
        _ value: String,
        allowed: CharacterSet
    ) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == value,
              !trimmed.hasPrefix("-"),
              trimmed.utf8.count <= 255 else {
            return false
        }
        return trimmed.unicodeScalars.allSatisfy(allowed.contains)
    }
}

enum RemoteConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var summary: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case let .failed(message): message
        }
    }

    var isConnected: Bool {
        self == .connected
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
