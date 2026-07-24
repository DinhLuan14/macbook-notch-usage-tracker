import Foundation

public enum NotchDisplayStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case full
    case iconCompact
    case progressRings
    case minimal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .full: "Full"
        case .iconCompact: "Icon Compact"
        case .progressRings: "Progress Rings"
        case .minimal: "Minimal"
        }
    }
}

public enum QuotaMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case used
    case remaining

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .used: "Used"
        case .remaining: "Remaining"
        }
    }
}

public enum RightSideDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case modelAndContext
    case claudeOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .modelAndContext: "Model + context"
        case .claudeOnly: "Claude only"
        }
    }
}

public struct DisplayPreferences: Codable, Equatable, Sendable {
    public var style: NotchDisplayStyle
    public var quotaMetric: QuotaMetric
    public var rightSideMode: RightSideDisplayMode
    public var showsResetTime: Bool
    public var showsEffort: Bool
    public var showsTokenCount: Bool

    public init(
        style: NotchDisplayStyle = .full,
        quotaMetric: QuotaMetric = .used,
        rightSideMode: RightSideDisplayMode = .modelAndContext,
        showsResetTime: Bool = true,
        showsEffort: Bool = true,
        showsTokenCount: Bool = true
    ) {
        self.style = style
        self.quotaMetric = quotaMetric
        self.rightSideMode = rightSideMode
        self.showsResetTime = showsResetTime
        self.showsEffort = showsEffort
        self.showsTokenCount = showsTokenCount
    }

    private enum CodingKeys: String, CodingKey {
        case style
        case quotaMetric
        case rightSideMode
        case showsResetTime
        case showsEffort
        case showsTokenCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(NotchDisplayStyle.self, forKey: .style) ?? .full
        quotaMetric = try container.decodeIfPresent(QuotaMetric.self, forKey: .quotaMetric) ?? .used
        rightSideMode = try container.decodeIfPresent(
            RightSideDisplayMode.self,
            forKey: .rightSideMode
        ) ?? .modelAndContext
        showsResetTime = try container.decodeIfPresent(Bool.self, forKey: .showsResetTime) ?? true
        showsEffort = try container.decodeIfPresent(Bool.self, forKey: .showsEffort) ?? true
        showsTokenCount = try container.decodeIfPresent(Bool.self, forKey: .showsTokenCount) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(quotaMetric, forKey: .quotaMetric)
        try container.encode(rightSideMode, forKey: .rightSideMode)
        try container.encode(showsResetTime, forKey: .showsResetTime)
        try container.encode(showsEffort, forKey: .showsEffort)
        try container.encode(showsTokenCount, forKey: .showsTokenCount)
    }
}
