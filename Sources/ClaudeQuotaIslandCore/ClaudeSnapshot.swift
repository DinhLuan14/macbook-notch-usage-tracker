import Foundation

public struct ClaudeSnapshotSource: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var isRemote: Bool

    public init(id: String, label: String, isRemote: Bool) {
        self.id = id
        self.label = label
        self.isRemote = isRemote
    }

    public static let local = ClaudeSnapshotSource(id: "local", label: "Local Mac", isRemote: false)
}

public struct ClaudeQuotaWindow: Codable, Equatable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public struct ClaudeSessionSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(resolvedSource.id)::\(sessionID)" }

    public var sessionID: String
    public var sourceID: String?
    public var sourceLabel: String?
    public var sourceIsRemote: Bool?
    public var sessionName: String?
    public var workingDirectory: String?
    public var projectDirectory: String?
    public var transcriptPath: String?
    public var modelID: String?
    public var modelDisplayName: String?
    public var effort: String?
    public var contextUsedPercentage: Double?
    public var contextWindowSize: Int?
    public var totalInputTokens: Int?
    public var totalOutputTokens: Int?
    public var fiveHour: ClaudeQuotaWindow?
    public var sevenDay: ClaudeQuotaWindow?
    public var quotaUpdatedAt: Date?
    public var updatedAt: Date

    public init(
        sessionID: String,
        sourceID: String? = ClaudeSnapshotSource.local.id,
        sourceLabel: String? = ClaudeSnapshotSource.local.label,
        sourceIsRemote: Bool? = false,
        sessionName: String? = nil,
        workingDirectory: String? = nil,
        projectDirectory: String? = nil,
        transcriptPath: String? = nil,
        modelID: String? = nil,
        modelDisplayName: String? = nil,
        effort: String? = nil,
        contextUsedPercentage: Double? = nil,
        contextWindowSize: Int? = nil,
        totalInputTokens: Int? = nil,
        totalOutputTokens: Int? = nil,
        fiveHour: ClaudeQuotaWindow? = nil,
        sevenDay: ClaudeQuotaWindow? = nil,
        quotaUpdatedAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.sessionID = sessionID
        self.sourceID = sourceID
        self.sourceLabel = sourceLabel
        self.sourceIsRemote = sourceIsRemote
        self.sessionName = sessionName
        self.workingDirectory = workingDirectory
        self.projectDirectory = projectDirectory
        self.transcriptPath = transcriptPath
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.effort = effort
        self.contextUsedPercentage = contextUsedPercentage
        self.contextWindowSize = contextWindowSize
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.quotaUpdatedAt = quotaUpdatedAt
        self.updatedAt = updatedAt
    }

    public var title: String {
        if let sessionName = sessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionName.isEmpty {
            return sessionName
        }
        if let workingDirectory, !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).lastPathComponent
        }
        return "Session \(sessionID.prefix(8))"
    }

    public var resolvedSource: ClaudeSnapshotSource {
        ClaudeSnapshotSource(
            id: sourceID ?? ClaudeSnapshotSource.local.id,
            label: sourceLabel ?? ClaudeSnapshotSource.local.label,
            isRemote: sourceIsRemote ?? false
        )
    }

    public var isQuotaAvailable: Bool {
        fiveHour != nil || sevenDay != nil
    }

    public func isFresh(at date: Date = .now, within interval: TimeInterval = 20) -> Bool {
        date.timeIntervalSince(updatedAt) <= interval
    }
}

public struct ClaudeStatusLinePayload: Decodable, Sendable {
    public struct Model: Decodable, Sendable {
        public var id: String?
        public var displayName: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    public struct Effort: Decodable, Sendable {
        public var level: String?
    }

    public struct ContextWindow: Decodable, Sendable {
        public var totalInputTokens: Int?
        public var totalOutputTokens: Int?
        public var contextWindowSize: Int?
        public var usedPercentage: Double?

        private enum CodingKeys: String, CodingKey {
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case contextWindowSize = "context_window_size"
            case usedPercentage = "used_percentage"
        }
    }

    public struct RateLimitWindow: Decodable, Sendable {
        public var usedPercentage: Double?
        public var resetsAt: Date?

        private enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case utilization
            case resetsAt = "resets_at"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercentage = try container.decodeIfPresent(Double.self, forKey: .usedPercentage)
                ?? container.decodeIfPresent(Double.self, forKey: .utilization)
            resetsAt = try container.decodeFlexibleDateIfPresent(forKey: .resetsAt)
        }
    }

    public struct RateLimits: Decodable, Sendable {
        public var fiveHour: RateLimitWindow?
        public var sevenDay: RateLimitWindow?

        private enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    public var sessionID: String?
    public var sessionName: String?
    public var workingDirectory: String?
    public var transcriptPath: String?
    public var model: Model?
    public var effort: Effort?
    public var contextWindow: ContextWindow?
    public var rateLimits: RateLimits?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case workingDirectory = "cwd"
        case transcriptPath = "transcript_path"
        case model
        case effort
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        if let seconds = try? decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = try decodeIfPresent(String.self, forKey: key), !string.isEmpty else {
            return nil
        }
        if let seconds = Double(string) {
            return Date(timeIntervalSince1970: seconds)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        return ISO8601DateFormatter().date(from: string)
    }
}
