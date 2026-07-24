import Foundation

public enum QuotaSnapshotSelector {
    public static func latest(in snapshots: [ClaudeSessionSnapshot]) -> ClaudeSessionSnapshot? {
        snapshots
            .filter(\.isQuotaAvailable)
            .max { effectiveQuotaDate($0) < effectiveQuotaDate($1) }
    }

    public static func effectiveQuotaDate(_ snapshot: ClaudeSessionSnapshot) -> Date {
        snapshot.quotaUpdatedAt ?? snapshot.updatedAt
    }
}
