import Foundation

public final class SnapshotStore: @unchecked Sendable {
    public static var defaultDirectoryURL: URL {
        if let override = ProcessInfo.processInfo.environment["CQI_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ClaudeQuotaIsland/sessions", isDirectory: true)
    }

    public let directoryURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL = SnapshotStore.defaultDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public func prepareDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    @discardableResult
    public func ingest(
        _ payload: ClaudeStatusLinePayload,
        at date: Date = .now,
        source: ClaudeSnapshotSource = .local
    ) throws -> ClaudeSessionSnapshot? {
        guard let sessionID = payload.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty else {
            return nil
        }

        try prepareDirectory()
        let url = fileURL(for: sessionID, sourceID: source.id)
        let existing = try? loadSnapshot(from: url)
        let snapshot = ClaudeSessionSnapshot(
            sessionID: sessionID,
            sourceID: source.id,
            sourceLabel: source.label,
            sourceIsRemote: source.isRemote,
            sessionName: payload.sessionName ?? existing?.sessionName,
            workingDirectory: payload.workingDirectory ?? existing?.workingDirectory,
            projectDirectory: existing?.projectDirectory ?? payload.workingDirectory,
            transcriptPath: payload.transcriptPath ?? existing?.transcriptPath,
            modelID: payload.model?.id ?? existing?.modelID,
            modelDisplayName: payload.model?.displayName ?? existing?.modelDisplayName,
            effort: payload.effort?.level ?? existing?.effort,
            contextUsedPercentage: payload.contextWindow?.usedPercentage ?? existing?.contextUsedPercentage,
            contextWindowSize: payload.contextWindow?.contextWindowSize ?? existing?.contextWindowSize,
            totalInputTokens: payload.contextWindow?.totalInputTokens ?? existing?.totalInputTokens,
            totalOutputTokens: payload.contextWindow?.totalOutputTokens ?? existing?.totalOutputTokens,
            fiveHour: quotaWindow(payload.rateLimits?.fiveHour) ?? existing?.fiveHour,
            sevenDay: quotaWindow(payload.rateLimits?.sevenDay) ?? existing?.sevenDay,
            quotaUpdatedAt: payloadHasQuota(payload) ? date : migratedQuotaDate(existing),
            updatedAt: date
        )
        try save(snapshot, to: url)
        return snapshot
    }

    @discardableResult
    public func mergeDiscovered(_ discovered: ClaudeSessionSnapshot) throws -> ClaudeSessionSnapshot {
        let source = discovered.resolvedSource
        let url = fileURL(for: discovered.sessionID, sourceID: source.id)
        try prepareDirectory()
        let existing = try? loadSnapshot(from: url)
        let snapshot = ClaudeSessionSnapshot(
            sessionID: discovered.sessionID,
            sourceID: source.id,
            sourceLabel: source.label,
            sourceIsRemote: source.isRemote,
            sessionName: discovered.sessionName ?? existing?.sessionName,
            workingDirectory: discovered.workingDirectory ?? existing?.workingDirectory,
            projectDirectory: discovered.projectDirectory ?? existing?.projectDirectory,
            transcriptPath: discovered.transcriptPath ?? existing?.transcriptPath,
            modelID: discovered.modelID ?? existing?.modelID,
            modelDisplayName: discovered.modelDisplayName ?? existing?.modelDisplayName,
            effort: discovered.effort ?? existing?.effort,
            contextUsedPercentage: existing?.contextUsedPercentage ?? discovered.contextUsedPercentage,
            contextWindowSize: existing?.contextWindowSize ?? discovered.contextWindowSize,
            totalInputTokens: existing?.totalInputTokens ?? discovered.totalInputTokens,
            totalOutputTokens: existing?.totalOutputTokens ?? discovered.totalOutputTokens,
            fiveHour: existing?.fiveHour ?? discovered.fiveHour,
            sevenDay: existing?.sevenDay ?? discovered.sevenDay,
            quotaUpdatedAt: migratedQuotaDate(existing) ?? discovered.quotaUpdatedAt,
            updatedAt: max(existing?.updatedAt ?? .distantPast, discovered.updatedAt)
        )
        try save(snapshot, to: url)
        return snapshot
    }

    public func loadSnapshots(
        newerThan maximumAge: TimeInterval? = 7 * 86_400,
        now: Date = .now
    ) throws -> [ClaudeSessionSnapshot] {
        try prepareDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? loadSnapshot(from: $0) }
            .filter { snapshot in
                guard let maximumAge else { return true }
                return now.timeIntervalSince(snapshot.updatedAt) <= maximumAge
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func pruneSnapshots(olderThan maximumAge: TimeInterval, now: Date = .now) throws {
        try prepareDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in urls where url.pathExtension == "json" {
            guard let snapshot = try? loadSnapshot(from: url),
                  now.timeIntervalSince(snapshot.updatedAt) > maximumAge else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
    }

    public func fileURL(for sessionID: String) -> URL {
        fileURL(for: sessionID, sourceID: ClaudeSnapshotSource.local.id)
    }

    public func fileURL(for sessionID: String, sourceID: String) -> URL {
        let namespacedID = sourceID == ClaudeSnapshotSource.local.id
            ? sessionID
            : "\(sourceID)::\(sessionID)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = namespacedID.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let prefix = String(cleaned.prefix(80))
        let hash = namespacedID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return directoryURL.appendingPathComponent("\(prefix)-\(String(hash, radix: 16)).json")
    }

    private func quotaWindow(_ payload: ClaudeStatusLinePayload.RateLimitWindow?) -> ClaudeQuotaWindow? {
        guard let usedPercentage = payload?.usedPercentage else { return nil }
        return ClaudeQuotaWindow(usedPercentage: usedPercentage, resetsAt: payload?.resetsAt)
    }

    private func payloadHasQuota(_ payload: ClaudeStatusLinePayload) -> Bool {
        payload.rateLimits?.fiveHour?.usedPercentage != nil
            || payload.rateLimits?.sevenDay?.usedPercentage != nil
    }

    private func migratedQuotaDate(_ snapshot: ClaudeSessionSnapshot?) -> Date? {
        guard let snapshot, snapshot.isQuotaAvailable else { return nil }
        return snapshot.quotaUpdatedAt ?? snapshot.updatedAt
    }

    private func loadSnapshot(from url: URL) throws -> ClaudeSessionSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeSessionSnapshot.self, from: Data(contentsOf: url))
    }

    private func save(_ snapshot: ClaudeSessionSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
