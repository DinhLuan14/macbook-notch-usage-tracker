import Foundation

public struct StatusLineInstallationPaths: Sendable {
    public var claudeDirectory: URL
    public var managedBinDirectory: URL
    public var cacheDirectory: URL

    public init(
        claudeDirectory: URL,
        managedBinDirectory: URL,
        cacheDirectory: URL
    ) {
        self.claudeDirectory = claudeDirectory
        self.managedBinDirectory = managedBinDirectory
        self.cacheDirectory = cacheDirectory
    }

    public static var `default`: StatusLineInstallationPaths {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let claudeDirectory: URL
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            claudeDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
        }
        return StatusLineInstallationPaths(
            claudeDirectory: claudeDirectory,
            managedBinDirectory: home.appendingPathComponent(".claude-quota-island/bin", isDirectory: true),
            cacheDirectory: SnapshotStore.defaultDirectoryURL
        )
    }

    public var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }
    public var scriptURL: URL { managedBinDirectory.appendingPathComponent("statusline") }
    public var helperURL: URL { managedBinDirectory.appendingPathComponent("claude-quota-island-helper") }
    public var delegateURL: URL { managedBinDirectory.appendingPathComponent("statusline-delegate") }
}

public struct StatusLineInstallationStatus: Equatable, Sendable {
    public var isConfigured: Bool
    public var helperExists: Bool
    public var scriptExists: Bool
    public var delegateExists: Bool
    public var wrapsExistingStatusLine: Bool
    public var hasConflict: Bool
    public var configuredCommand: String?

    public var isHealthy: Bool {
        isConfigured
            && helperExists
            && scriptExists
            && (!wrapsExistingStatusLine || delegateExists)
    }
}

public enum StatusLineInstallerError: LocalizedError, Sendable {
    case invalidSettings
    case existingStatusLine(command: String?)
    case executableMissing

    public var errorDescription: String? {
        switch self {
        case .invalidSettings:
            "Claude settings.json must contain a top-level JSON object."
        case let .existingStatusLine(command):
            command.map { "Claude Code already uses a custom status line: \($0)" }
                ?? "Claude Code already uses a custom status line."
        case .executableMissing:
            "The app executable could not be located for the status-line helper."
        }
    }
}

public final class StatusLineInstaller: @unchecked Sendable {
    public static let originalStatusLineKey = "_claudeQuotaIslandOriginalStatusLine"

    public let paths: StatusLineInstallationPaths
    private let fileManager: FileManager

    public init(
        paths: StatusLineInstallationPaths = .default,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func status() throws -> StatusLineInstallationStatus {
        let settings = try loadSettings()
        let statusLine = settings["statusLine"] as? [String: Any]
        let command = statusLine?["command"] as? String
        let isConfigured = command == paths.scriptURL.path
        let wrapsExistingStatusLine = isConfigured && settings[Self.originalStatusLineKey] != nil
        return StatusLineInstallationStatus(
            isConfigured: isConfigured,
            helperExists: fileManager.isExecutableFile(atPath: paths.helperURL.path),
            scriptExists: fileManager.isExecutableFile(atPath: paths.scriptURL.path),
            delegateExists: fileManager.isExecutableFile(atPath: paths.delegateURL.path),
            wrapsExistingStatusLine: wrapsExistingStatusLine,
            hasConflict: settings["statusLine"] != nil && !isConfigured,
            configuredCommand: command
        )
    }

    @discardableResult
    public func install(
        executableURL: URL,
        preserveExistingStatusLine: Bool
    ) throws -> StatusLineInstallationStatus {
        var settings = try loadSettings()
        let current = try status()

        if current.hasConflict && !preserveExistingStatusLine {
            throw StatusLineInstallerError.existingStatusLine(command: current.configuredCommand)
        }

        try fileManager.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)
        try preparePrivateDirectory(paths.managedBinDirectory)
        try preparePrivateDirectory(paths.cacheDirectory)
        try installHelper(from: executableURL)

        if current.hasConflict {
            guard let existingStatusLine = settings["statusLine"],
                  let existingCommand = current.configuredCommand,
                  !existingCommand.isEmpty else {
                throw StatusLineInstallerError.existingStatusLine(command: current.configuredCommand)
            }
            settings[Self.originalStatusLineKey] = existingStatusLine
            try writeExecutable(
                "#!/bin/bash\n# Original Claude Code status line preserved by Claude Quota Island.\n\(existingCommand)\n",
                to: paths.delegateURL
            )
        }

        try writeExecutable(managedScript(), to: paths.scriptURL)
        settings["statusLine"] = [
            "type": "command",
            "command": paths.scriptURL.path,
            "padding": 2,
            "refreshInterval": 5,
        ]
        try writeSettingsWithBackup(settings)
        return try status()
    }

    @discardableResult
    public func repair(executableURL: URL) throws -> StatusLineInstallationStatus {
        let current = try status()
        guard current.isConfigured else {
            return try install(executableURL: executableURL, preserveExistingStatusLine: current.hasConflict)
        }
        try preparePrivateDirectory(paths.managedBinDirectory)
        try preparePrivateDirectory(paths.cacheDirectory)
        try installHelper(from: executableURL)
        try writeExecutable(managedScript(), to: paths.scriptURL)
        if current.wrapsExistingStatusLine && !current.delegateExists {
            let settings = try loadSettings()
            let original = settings[Self.originalStatusLineKey] as? [String: Any]
            guard let command = original?["command"] as? String, !command.isEmpty else {
                throw StatusLineInstallerError.existingStatusLine(command: nil)
            }
            try writeExecutable(
                "#!/bin/bash\n# Original Claude Code status line preserved by Claude Quota Island.\n\(command)\n",
                to: paths.delegateURL
            )
        }
        return try status()
    }

    @discardableResult
    public func uninstall() throws -> StatusLineInstallationStatus {
        var settings = try loadSettings()
        let current = try status()

        if current.isConfigured {
            if let original = settings[Self.originalStatusLineKey] {
                settings["statusLine"] = original
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            settings.removeValue(forKey: Self.originalStatusLineKey)
            try writeSettingsWithBackup(settings)
        }

        for url in [paths.scriptURL, paths.delegateURL, paths.helperURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return try status()
    }

    public func managedScript() -> String {
        let helper = Self.shellQuote(paths.helperURL.path)
        let delegate = Self.shellQuote(paths.delegateURL.path)
        let cache = Self.shellQuote(paths.cacheDirectory.path)
        return """
        #!/bin/bash
        # Claude Quota Island status-line bridge. Fail-open by design.
        input=$(cat)
        helper=\(helper)
        delegate=\(delegate)
        cache=\(cache)

        if [ -x "$delegate" ]; then
          if [ -x "$helper" ]; then
            printf '%s' "$input" | CQI_CACHE_DIR="$cache" "$helper" --statusline-ingest >/dev/null 2>&1
          fi
          printf '%s' "$input" | "$delegate"
        elif [ -x "$helper" ]; then
          printf '%s' "$input" | CQI_CACHE_DIR="$cache" "$helper" --statusline-render 2>/dev/null
        fi
        exit 0
        """
    }

    private func installHelper(from executableURL: URL) throws {
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw StatusLineInstallerError.executableMissing
        }
        let data = try Data(contentsOf: executableURL, options: .mappedIfSafe)
        try data.write(to: paths.helperURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.helperURL.path)
    }

    private func loadSettings() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: paths.settingsURL.path) else { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.settingsURL))
        guard let settings = object as? [String: Any] else {
            throw StatusLineInstallerError.invalidSettings
        }
        return settings
    }

    private func writeSettingsWithBackup(_ settings: [String: Any]) throws {
        if fileManager.fileExists(atPath: paths.settingsURL.path) {
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
            let suffix = UUID().uuidString.prefix(8)
            let backupURL = paths.settingsURL.appendingPathExtension("backup.\(timestamp).\(suffix)")
            try fileManager.copyItem(at: paths.settingsURL, to: backupURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backupURL.path
            )
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: paths.settingsURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.settingsURL.path)
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func preparePrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
