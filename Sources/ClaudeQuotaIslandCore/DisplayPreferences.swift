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

public struct DisplayPreferences: Codable, Equatable, Sendable {
    public var style: NotchDisplayStyle
    public var quotaMetric: QuotaMetric
    public var showsResetTime: Bool
    public var showsEffort: Bool
    public var showsTokenCount: Bool

    public init(
        style: NotchDisplayStyle = .full,
        quotaMetric: QuotaMetric = .used,
        showsResetTime: Bool = true,
        showsEffort: Bool = true,
        showsTokenCount: Bool = true
    ) {
        self.style = style
        self.quotaMetric = quotaMetric
        self.showsResetTime = showsResetTime
        self.showsEffort = showsEffort
        self.showsTokenCount = showsTokenCount
    }
}
