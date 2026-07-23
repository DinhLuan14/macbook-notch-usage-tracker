import Foundation

public enum QuotaFormatter {
    public static func percentage(_ usedPercentage: Double?, metric: QuotaMetric) -> Int? {
        guard let usedPercentage, usedPercentage.isFinite else { return nil }
        let used = min(max(usedPercentage, 0), 100)
        let value = metric == .used ? used : 100 - used
        return Int(value.rounded())
    }

    public static func resetDuration(
        until resetDate: Date?,
        now: Date = .now,
        compact: Bool = false
    ) -> String? {
        guard let resetDate else { return nil }
        let seconds = max(0, Int(resetDate.timeIntervalSince(now).rounded(.down)))
        if seconds == 0 { return "now" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d\(hours)h" : "\(days)d"
        }
        if hours > 0 {
            if compact {
                return minutes > 0 ? "\(hours)h\(minutes)" : "\(hours)h"
            }
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }

    public static func tokenCount(_ count: Int?) -> String? {
        guard let count, count >= 0 else { return nil }
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 { return "\(Int((Double(count) / 1_000).rounded()))k" }

        let millions = Double(count) / 1_000_000
        if millions >= 10 || millions.rounded() == millions {
            return "\(Int(millions.rounded()))m"
        }
        return String(format: "%.1fm", millions)
    }
}
