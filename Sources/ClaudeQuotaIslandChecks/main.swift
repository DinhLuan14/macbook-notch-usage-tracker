import ClaudeQuotaIslandCore
import Darwin
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-quota-island-checks-\(UUID().uuidString)", isDirectory: true)
}

let fullPayload = """
{
  "session_id": "session-abc",
  "session_name": "Personal project",
  "cwd": "/tmp/example/project",
  "transcript_path": "/tmp/example/.claude/session-abc.jsonl",
  "model": {"id": "claude-opus-4-8", "display_name": "Opus 4.8"},
  "effort": {"level": "high"},
  "context_window": {
    "total_input_tokens": 126000,
    "total_output_tokens": 5000,
    "context_window_size": 200000,
    "used_percentage": 63
  },
  "rate_limits": {
    "five_hour": {"used_percentage": 31, "resets_at": 1800000000},
    "seven_day": {"used_percentage": 34, "resets_at": "2027-01-15T12:00:00Z"}
  }
}
"""

func checkSnapshotPipeline() throws {
    let payload = try JSONDecoder().decode(ClaudeStatusLinePayload.self, from: Data(fullPayload.utf8))
    try expect(payload.sessionID == "session-abc", "session_id decoding")
    try expect(payload.model?.displayName == "Opus 4.8", "model decoding")
    try expect(payload.contextWindow?.totalInputTokens == 126_000, "context token decoding")
    try expect(payload.rateLimits?.fiveHour?.usedPercentage == 31, "five-hour quota decoding")

    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SnapshotStore(directoryURL: root)
    _ = try store.ingest(payload)
    let directoryMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions]
        as? NSNumber
    let snapshotURL = store.fileURL(for: "session-abc")
    let snapshotMode = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)[.posixPermissions]
        as? NSNumber
    try expect(directoryMode?.intValue == 0o700, "snapshot directory owner-only permissions")
    try expect(snapshotMode?.intValue == 0o600, "snapshot file owner-only permissions")

    let update = """
    {"session_id":"session-abc","context_window":{"used_percentage":70,"total_input_tokens":140000}}
    """
    _ = try store.ingest(JSONDecoder().decode(ClaudeStatusLinePayload.self, from: Data(update.utf8)))
    let snapshot = try store.loadSnapshots(newerThan: nil)[0]
    try expect(snapshot.contextUsedPercentage == 70, "context update")
    try expect(snapshot.fiveHour?.usedPercentage == 31, "last-known quota preservation")
    try expect(snapshot.quotaUpdatedAt != nil, "quota capture timestamp preservation")
    try expect(snapshot.projectDirectory == "/tmp/example/project", "project directory inference")

    let rendered = try StatusLineCommand.process(
        Data(fullPayload.utf8),
        mode: .ingestAndRender,
        store: store
    )
    try expect(rendered == "[Opus 4.8] 63% context", "status-line rendering")
}

func checkSourceAwareSnapshots() throws {
    let payload = try JSONDecoder().decode(ClaudeStatusLinePayload.self, from: Data(fullPayload.utf8))
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SnapshotStore(directoryURL: root)
    let remote = ClaudeSnapshotSource(id: "ssh-primary", label: "Development", isRemote: true)

    _ = try store.ingest(payload, source: .local)
    _ = try store.ingest(payload, source: remote)

    let snapshots = try store.loadSnapshots(newerThan: nil)
    try expect(snapshots.count == 2, "local and SSH sessions with the same Claude ID remain distinct")
    try expect(Set(snapshots.map(\.id)).count == 2, "source-aware SwiftUI identities")
    try expect(snapshots.contains { $0.resolvedSource == .local }, "local source metadata")
    try expect(snapshots.contains { $0.resolvedSource == remote }, "remote source metadata")
    try expect(
        store.fileURL(for: "session-abc")
            != store.fileURL(for: "session-abc", sourceID: remote.id),
        "source-aware snapshot paths"
    )

    let discovered = ClaudeSessionSnapshot(
        sessionID: "session-abc",
        sourceID: remote.id,
        sourceLabel: remote.label,
        sourceIsRemote: true,
        sessionName: "Example · session",
        workingDirectory: "/srv/projects/example",
        projectDirectory: "/srv/projects/example",
        modelID: "claude-opus-4-8",
        modelDisplayName: "Opus 4.8",
        totalInputTokens: 99_000,
        updatedAt: Date.now.addingTimeInterval(-60)
    )
    let merged = try store.mergeDiscovered(discovered)
    try expect(merged.sessionName == "Example · session", "discovered session metadata merge")
    try expect(merged.projectDirectory == "/srv/projects/example", "discovered project directory merge")
    try expect(merged.contextUsedPercentage == 63, "live context wins over transcript discovery")
    try expect(merged.fiveHour?.usedPercentage == 31, "live quota wins over transcript discovery")
    try expect(merged.quotaUpdatedAt != nil, "quota capture timestamp survives discovery")
}

func checkFormatting() throws {
    try expect(DisplayPreferences().showsResetTime, "reset time enabled by default")
    try expect(
        DisplayPreferences().rightSideMode == .modelAndContext,
        "model and context enabled by default"
    )
    try expect(QuotaFormatter.percentage(31, metric: .used) == 31, "used quota")
    try expect(QuotaFormatter.percentage(31, metric: .remaining) == 69, "remaining quota")
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reset = now.addingTimeInterval(4 * 3_600 + 34 * 60)
    try expect(QuotaFormatter.resetDuration(until: reset, now: now) == "4h34m", "full reset duration")
    try expect(QuotaFormatter.resetDuration(until: reset, now: now, compact: true) == "4h34", "compact reset duration")
    try expect(QuotaFormatter.tokenCount(126_000) == "126k", "token formatting")
}

func checkQuotaSelectionAndPreferenceMigration() throws {
    let olderTimestampedQuota = ClaudeSessionSnapshot(
        sessionID: "older",
        fiveHour: ClaudeQuotaWindow(usedPercentage: 2, resetsAt: nil),
        sevenDay: ClaudeQuotaWindow(usedPercentage: 45, resetsAt: nil),
        quotaUpdatedAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 3_000)
    )
    let newerLegacyQuota = ClaudeSessionSnapshot(
        sessionID: "newer",
        fiveHour: ClaudeQuotaWindow(usedPercentage: 17, resetsAt: nil),
        sevenDay: ClaudeQuotaWindow(usedPercentage: 47, resetsAt: nil),
        quotaUpdatedAt: nil,
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
    let selected = QuotaSnapshotSelector.latest(
        in: [olderTimestampedQuota, newerLegacyQuota]
    )
    try expect(
        selected?.sessionID == "newer",
        "newer legacy quota must beat an older timestamped quota"
    )

    let now = Date(timeIntervalSince1970: 10_000)
    let expired = ClaudeQuotaWindow(
        usedPercentage: 90,
        resetsAt: now.addingTimeInterval(-1)
    )
    let active = ClaudeQuotaWindow(
        usedPercentage: 20,
        resetsAt: now.addingTimeInterval(1)
    )
    try expect(expired.current(at: now) == nil, "expired quota window is hidden")
    try expect(active.current(at: now) != nil, "active quota window remains visible")

    let legacyPreferences = """
    {
      "style": "iconCompact",
      "quotaMetric": "remaining",
      "showsResetTime": false,
      "showsEffort": false,
      "showsTokenCount": true
    }
    """
    let decoded = try JSONDecoder().decode(
        DisplayPreferences.self,
        from: Data(legacyPreferences.utf8)
    )
    try expect(decoded.style == .iconCompact, "legacy display style migration")
    try expect(decoded.quotaMetric == .remaining, "legacy quota metric migration")
    try expect(
        decoded.rightSideMode == .modelAndContext,
        "legacy preferences default to model and context"
    )
    try expect(!decoded.showsResetTime, "legacy reset preference preservation")
}

func checkNotchPanelAlignment() throws {
    let physicalOrigin = NotchPanelFrameResolver.originX(
        centerX: 1_000,
        leftWidth: 140,
        notchWidth: 180,
        totalWidth: 380,
        hasPhysicalNotch: true
    )
    try expect(
        physicalOrigin + 140 + 90 == 1_000,
        "physical notch spacer remains centered with asymmetric side widths"
    )

    let fallbackOrigin = NotchPanelFrameResolver.originX(
        centerX: 1_000,
        leftWidth: 140,
        notchWidth: 180,
        totalWidth: 380,
        hasPhysicalNotch: false
    )
    try expect(
        fallbackOrigin + 190 == 1_000,
        "fallback island remains centered by total width"
    )
}

func checkInstallerRoundTrip() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = StatusLineInstallationPaths(
        claudeDirectory: root.appendingPathComponent("claude"),
        managedBinDirectory: root.appendingPathComponent("managed/bin"),
        cacheDirectory: root.appendingPathComponent("cache/sessions")
    )
    try FileManager.default.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)
    let original: [String: Any] = [
        "theme": "dark",
        "statusLine": ["type": "command", "command": "/usr/local/bin/my-status", "padding": 1],
    ]
    try JSONSerialization.data(withJSONObject: original, options: [.prettyPrinted])
        .write(to: paths.settingsURL)

    let executable = root.appendingPathComponent("fake-app")
    try Data("fake executable".utf8).write(to: executable)
    let installer = StatusLineInstaller(paths: paths)
    let initialStatus = try installer.status()
    try expect(initialStatus.hasConflict, "custom status-line detection")

    do {
        _ = try installer.install(executableURL: executable, preserveExistingStatusLine: false)
        throw CheckFailure.failed("conflicting status line must not be overwritten")
    } catch is StatusLineInstallerError {
        // Expected.
    }

    let installed = try installer.install(executableURL: executable, preserveExistingStatusLine: true)
    try expect(installed.isHealthy, "wrapper installation")
    try expect(installed.wrapsExistingStatusLine, "wrapper marker")
    var installedSettings = try JSONSerialization.jsonObject(
        with: Data(contentsOf: paths.settingsURL)
    ) as? [String: Any]
    var installedStatusLine = installedSettings?["statusLine"] as? [String: Any]
    try expect(
        (installedStatusLine?["refreshInterval"] as? NSNumber)?.intValue
            == StatusLineInstaller.refreshInterval,
        "five-second status-line refresh installation"
    )

    installedStatusLine?.removeValue(forKey: "refreshInterval")
    installedSettings?["statusLine"] = installedStatusLine
    try JSONSerialization.data(
        withJSONObject: installedSettings ?? [:],
        options: [.prettyPrinted]
    ).write(to: paths.settingsURL)
    let legacyStatus = try installer.status()
    try expect(
        !legacyStatus.isHealthy,
        "legacy installation without refresh interval needs repair"
    )
    let refreshed = try installer.repair(executableURL: executable)
    try expect(refreshed.isHealthy, "refresh interval repair")
    let refreshedSettings = try JSONSerialization.jsonObject(
        with: Data(contentsOf: paths.settingsURL)
    ) as? [String: Any]
    let refreshedStatusLine = refreshedSettings?["statusLine"] as? [String: Any]
    try expect(
        (refreshedStatusLine?["refreshInterval"] as? NSNumber)?.intValue
            == StatusLineInstaller.refreshInterval,
        "repair restores five-second status-line refresh"
    )
    let managedMode = try FileManager.default.attributesOfItem(
        atPath: paths.managedBinDirectory.path
    )[.posixPermissions] as? NSNumber
    let helperMode = try FileManager.default.attributesOfItem(
        atPath: paths.helperURL.path
    )[.posixPermissions] as? NSNumber
    let settingsMode = try FileManager.default.attributesOfItem(
        atPath: paths.settingsURL.path
    )[.posixPermissions] as? NSNumber
    try expect(managedMode?.intValue == 0o700, "managed directory owner-only permissions")
    try expect(helperMode?.intValue == 0o700, "helper owner-only permissions")
    try expect(settingsMode?.intValue == 0o600, "Claude settings owner-only permissions")
    let backups = try FileManager.default.contentsOfDirectory(
        at: paths.claudeDirectory,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.contains("settings.json.backup.") }
    try expect(!backups.isEmpty, "Claude settings backup creation")
    for backup in backups {
        let mode = try FileManager.default.attributesOfItem(
            atPath: backup.path
        )[.posixPermissions] as? NSNumber
        try expect(mode?.intValue == 0o600, "Claude settings backup owner-only permissions")
    }
    let script = try String(contentsOf: paths.scriptURL, encoding: .utf8)
    try expect(script.contains("--statusline-ingest"), "ingest helper command")

    try FileManager.default.removeItem(at: paths.delegateURL)
    let brokenWrapper = try installer.status()
    try expect(!brokenWrapper.isHealthy, "missing wrapper delegate health check")
    let repaired = try installer.repair(executableURL: executable)
    try expect(repaired.isHealthy, "wrapper delegate repair")

    _ = try installer.uninstall()
    let restoredObject = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.settingsURL))
    guard let restoredSettings = restoredObject as? [String: Any],
          let restoredStatusLine = restoredSettings["statusLine"] as? [String: Any] else {
        throw CheckFailure.failed("restored settings structure")
    }
    try expect(restoredStatusLine["command"] as? String == "/usr/local/bin/my-status", "status-line restoration")
    try expect(restoredSettings["theme"] as? String == "dark", "unrelated settings preservation")
}

do {
    try checkSnapshotPipeline()
    try checkSourceAwareSnapshots()
    try checkFormatting()
    try checkQuotaSelectionAndPreferenceMigration()
    try checkNotchPanelAlignment()
    try checkInstallerRoundTrip()
    print("All ClaudeQuotaIsland checks passed.")
    exit(0)
} catch {
    FileHandle.standardError.write(Data("Check failed: \(error)\n".utf8))
    exit(1)
}
