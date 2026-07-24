import AppKit
import ClaudeQuotaIslandCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    nonisolated static let automaticSelectionID = "automatic"
    nonisolated static let sessionRetention: TimeInterval = 30 * 24 * 60 * 60

    @Published var displayPreferences: DisplayPreferences {
        didSet {
            persistDisplayPreferences()
            onLayoutChanged?()
        }
    }
    @Published var selectedSessionID: String? {
        didSet {
            if let selectedSessionID {
                defaults.set(selectedSessionID, forKey: Self.selectedSessionDefaultsKey)
            } else {
                defaults.removeObject(forKey: Self.selectedSessionDefaultsKey)
            }
            onLayoutChanged?()
        }
    }
    @Published var selectedProjectID: String? {
        didSet {
            if let selectedProjectID {
                defaults.set(selectedProjectID, forKey: Self.selectedProjectDefaultsKey)
            } else {
                defaults.removeObject(forKey: Self.selectedProjectDefaultsKey)
            }
            onLayoutChanged?()
        }
    }
    @Published var preferredDisplayID: String {
        didSet {
            defaults.set(preferredDisplayID, forKey: Self.preferredDisplayDefaultsKey)
            onLayoutChanged?()
        }
    }
    @Published var preferredSourceID: String {
        didSet {
            defaults.set(preferredSourceID, forKey: Self.preferredSourceDefaultsKey)
            selectedSessionID = nil
            selectedProjectID = nil
            updateRemoteConnectionForSelection()
            onLayoutChanged?()
        }
    }
    @Published var remoteConfiguration: RemoteClaudeConfiguration {
        didSet {
            persistRemoteConfiguration()
            onLayoutChanged?()
        }
    }
    @Published private(set) var remoteConnectionState: RemoteConnectionState = .disconnected
    @Published private(set) var remoteSetupIsBusy = false
    @Published private(set) var remoteDiscoveryIsBusy = false
    @Published private(set) var isIslandExpanded = false {
        didSet { onExpansionChanged?(isIslandExpanded) }
    }
    @Published private(set) var snapshots: [ClaudeSessionSnapshot] = [] {
        didSet { onLayoutChanged?() }
    }
    @Published private(set) var installationStatus: StatusLineInstallationStatus?
    @Published private(set) var statusMessage = "Waiting for Claude Code status-line data."
    @Published private(set) var launchAtLoginEnabled = false

    var onLayoutChanged: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?

    private static let displayPreferencesDefaultsKey = "display.preferences"
    private static let selectedSessionDefaultsKey = "session.selectedID"
    private static let selectedProjectDefaultsKey = "project.selectedID"
    private static let preferredDisplayDefaultsKey = "display.preferredID"
    nonisolated static let preferredSourceDefaultsKey = "source.preferredID"
    nonisolated static let remoteConfigurationDefaultsKey = "source.remoteConfiguration"
    private static let legacyDefaultsSuite = "com.luan.claude-quota-island"
    private static let legacyMigrationDefaultsKey = "migration.legacyDefaults.v1"

    private let defaults: UserDefaults
    private let snapshotStore: SnapshotStore
    private let statusLineInstaller: StatusLineInstaller
    private let executableURL: URL?
    private var monitorTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?
    private var remoteDiscoveryTask: Task<Void, Never>?
    private var remoteReconnectTask: Task<Void, Never>?
    private var localDiscoveryTask: Task<Void, Never>?
    private let remoteTunnel = SSHRemoteTunnel()
    private var remotePayloadServer: RemotePayloadServer?
    private var remoteConnectionDesired = false

    nonisolated static func runtimeDefaults() -> UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["CQI_DEFAULTS_SUITE"],
           !suite.isEmpty,
           let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        return .standard
    }

    init(
        defaults: UserDefaults = AppModel.runtimeDefaults(),
        snapshotStore: SnapshotStore = SnapshotStore(),
        statusLineInstaller: StatusLineInstaller = StatusLineInstaller(),
        executableURL: URL? = Bundle.main.executableURL
    ) {
        Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        self.defaults = defaults
        self.snapshotStore = snapshotStore
        self.statusLineInstaller = statusLineInstaller
        self.executableURL = executableURL

        if let data = defaults.data(forKey: Self.displayPreferencesDefaultsKey),
           let preferences = try? JSONDecoder().decode(DisplayPreferences.self, from: data) {
            displayPreferences = preferences
        } else {
            displayPreferences = DisplayPreferences()
        }
        selectedSessionID = defaults.string(forKey: Self.selectedSessionDefaultsKey)
        selectedProjectID = defaults.string(forKey: Self.selectedProjectDefaultsKey)
        preferredDisplayID = defaults.string(forKey: Self.preferredDisplayDefaultsKey)
            ?? Self.automaticSelectionID
        if let data = defaults.data(forKey: Self.remoteConfigurationDefaultsKey),
           let configuration = try? JSONDecoder().decode(RemoteClaudeConfiguration.self, from: data) {
            remoteConfiguration = configuration
        } else {
            remoteConfiguration = RemoteClaudeConfiguration()
        }
        preferredSourceID = defaults.string(forKey: Self.preferredSourceDefaultsKey)
            ?? Self.automaticSelectionID
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
        isIslandExpanded = ProcessInfo.processInfo.environment["CQI_HOLD_EXPANDED"] == "1"
    }

    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard ProcessInfo.processInfo.environment["CQI_DEFAULTS_SUITE"] == nil,
              Bundle.main.bundleIdentifier == "io.github.dinhluan14.macbook-notch-usage-tracker",
              !defaults.bool(forKey: legacyMigrationDefaultsKey) else {
            return
        }

        if let legacy = UserDefaults(suiteName: legacyDefaultsSuite) {
            let keys = [
                displayPreferencesDefaultsKey,
                selectedSessionDefaultsKey,
                selectedProjectDefaultsKey,
                preferredDisplayDefaultsKey,
                preferredSourceDefaultsKey,
                remoteConfigurationDefaultsKey,
            ]
            for key in keys where defaults.object(forKey: key) == nil {
                if let value = legacy.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(true, forKey: legacyMigrationDefaultsKey)
    }

    var recentSnapshots: [ClaudeSessionSnapshot] {
        sourceSnapshots
    }

    var recentProjects: [ClaudeRecentProject] {
        let sourceFiltered = snapshots.filter { snapshot in
            switch preferredSourceID {
            case Self.automaticSelectionID:
                true
            case ClaudeSnapshotSource.local.id:
                snapshot.resolvedSource.id == ClaudeSnapshotSource.local.id
            default:
                snapshot.resolvedSource.id == preferredSourceID
            }
        }
        return ClaudeRecentProject.groups(
            snapshots: sourceFiltered,
            remoteConfiguration: remoteConfiguration
        )
    }

    var selectedSnapshot: ClaudeSessionSnapshot? {
        if let selectedSessionID,
           let selected = sourceSnapshots.first(where: {
               $0.id == selectedSessionID || $0.sessionID == selectedSessionID
           }) {
            return selected
        }
        return sourceSnapshots.first(where: { $0.isFresh() }) ?? sourceSnapshots.first
    }

    var quotaSnapshot: ClaudeSessionSnapshot? {
        let candidates = snapshots.filter { snapshot in
            guard snapshot.isQuotaAvailable else { return false }
            switch preferredSourceID {
            case Self.automaticSelectionID:
                return true
            case ClaudeSnapshotSource.local.id:
                return snapshot.resolvedSource.id == ClaudeSnapshotSource.local.id
            default:
                return snapshot.resolvedSource.id == preferredSourceID
            }
        }
        return QuotaSnapshotSelector.latest(in: candidates)
    }

    var remoteSourceID: String { remoteConfiguration.sourceID }

    var sourceSelectionSummary: String {
        switch preferredSourceID {
        case Self.automaticSelectionID: "Automatic · local + SSH"
        case ClaudeSnapshotSource.local.id: ClaudeSnapshotSource.local.label
        case remoteSourceID: "SSH · \(remoteConfiguration.displayName)"
        default: preferredSourceID
        }
    }

    private var sourceSnapshots: [ClaudeSessionSnapshot] {
        let sourceFiltered = switch preferredSourceID {
        case Self.automaticSelectionID:
            snapshots
        case ClaudeSnapshotSource.local.id:
            snapshots.filter { $0.resolvedSource.id == ClaudeSnapshotSource.local.id }
        default:
            snapshots.filter { $0.resolvedSource.id == preferredSourceID }
        }
        if let selectedProjectID,
           let project = ClaudeRecentProject.groups(
               snapshots: sourceFiltered,
               remoteConfiguration: remoteConfiguration
           ).first(where: { $0.id == selectedProjectID }) {
            return project.sessions
        }
        return sourceFiltered.filter(remoteSnapshotIsSelected)
    }

    private func remoteSnapshotIsSelected(_ snapshot: ClaudeSessionSnapshot) -> Bool {
        guard snapshot.resolvedSource.id == remoteSourceID,
              !remoteConfiguration.projectPaths.isEmpty else {
            return true
        }
        guard let workingDirectory = snapshot.workingDirectory else { return false }
        let normalized = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        return remoteConfiguration.projectPaths.contains { projectPath in
            normalized == projectPath || normalized.hasPrefix(projectPath + "/")
        }
    }

    var selectedSessionBindingID: String {
        get {
            guard let selectedSessionID else { return Self.automaticSelectionID }
            return sourceSnapshots.first(where: {
                $0.id == selectedSessionID || $0.sessionID == selectedSessionID
            })?.id ?? selectedSessionID
        }
        set { selectedSessionID = newValue == Self.automaticSelectionID ? nil : newValue }
    }

    var selectedProjectBindingID: String {
        get {
            guard let selectedProjectID,
                  recentProjects.contains(where: { $0.id == selectedProjectID }) else {
                return Self.automaticSelectionID
            }
            return selectedProjectID
        }
        set {
            selectProject(newValue == Self.automaticSelectionID ? nil : newValue)
        }
    }

    var statusLineSummary: String {
        guard let installationStatus else { return "Checking…" }
        if installationStatus.isHealthy {
            return installationStatus.wrapsExistingStatusLine
                ? "Connected · existing status line preserved"
                : "Connected"
        }
        if installationStatus.hasConflict {
            return "Custom status line detected"
        }
        if installationStatus.isConfigured {
            return "Needs repair"
        }
        return "Not installed"
    }

    var statusLineIsHealthy: Bool {
        installationStatus?.isHealthy == true
    }

    var quotaDataIsCurrent: Bool {
        guard let quotaSnapshot else { return false }
        return quotaSnapshot.fiveHour?.current() != nil
            || quotaSnapshot.sevenDay?.current() != nil
    }

    var quotaDataSummary: String {
        if quotaDataIsCurrent { return "Current" }
        if quotaSnapshot != nil { return "Expired · send a Claude turn" }
        return "Waiting for a Claude turn"
    }

    func start() {
        refreshSnapshots()
        refreshInstallationStatus(autoRepair: true)
        startSnapshotMonitoring()
        startLocalDiscovery()
        updateRemoteConnectionForSelection()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        hoverCloseTask?.cancel()
        hoverCloseTask = nil
        localDiscoveryTask?.cancel()
        localDiscoveryTask = nil
        disconnectRemote()
    }

    func showSettings() {
        onShowSettings?()
    }

    func selectSession(_ id: String?) {
        if let id,
           let session = snapshots.first(where: { $0.id == id || $0.sessionID == id }) {
            selectedProjectID = ClaudeRecentProject.projectID(
                for: session,
                remoteConfiguration: remoteConfiguration
            )
        }
        selectedSessionID = id
    }

    func selectProject(_ id: String?) {
        selectedProjectID = id
        selectedSessionID = nil
    }

    func addRemoteProjectPath(_ value: String) -> Bool {
        guard let path = RemoteClaudeConfiguration.normalizedProjectPath(value) else {
            statusMessage = "Project folder must be an absolute path on the SSH server."
            return false
        }
        guard !remoteConfiguration.projectPaths.contains(path) else {
            statusMessage = "That remote project folder is already selected."
            return false
        }
        remoteConfiguration.projectPaths.append(path)
        remoteConfiguration.projectPaths = RemoteClaudeConfiguration.normalizedProjectPaths(
            remoteConfiguration.projectPaths
        )
        statusMessage = "Project added. Choose Repair & Connect to install its wrapper."
        return true
    }

    func removeRemoteProjectPath(_ path: String) {
        remoteConfiguration.projectPaths.removeAll { $0 == path }
        statusMessage = "Project removed from this Mac's filter. Choose Repair & Connect to apply remotely."
    }

    func installAndConnectRemote() {
        guard !remoteSetupIsBusy else { return }
        guard remoteConfiguration.isValid else {
            remoteConnectionState = .failed("Invalid SSH settings")
            statusMessage = SSHRemoteError.invalidConfiguration.localizedDescription
            return
        }

        remoteSetupIsBusy = true
        remoteConnectionState = .connecting
        statusMessage = "Installing the SSH status-line wrapper on \(remoteConfiguration.target)…"
        let configuration = remoteConfiguration
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    try SSHRemoteInstaller.install(configuration)
                }.value
                guard let self else { return }
                self.remoteConfiguration.isInstalled = true
                self.remoteSetupIsBusy = false
                self.statusMessage = "Remote wrapper installed. Starting SSH tunnel…"
                self.connectRemote()
            } catch {
                self?.remoteSetupIsBusy = false
                self?.remoteConnectionState = .failed(error.localizedDescription)
                self?.statusMessage = "Remote install failed: \(error.localizedDescription)"
            }
        }
    }

    func connectRemote() {
        remoteConnectionDesired = true
        remoteReconnectTask?.cancel()
        remoteReconnectTask = nil
        guard remoteConfiguration.isInstalled else {
            remoteConnectionDesired = false
            remoteConnectionState = .disconnected
            statusMessage = "Install the remote wrapper before connecting."
            return
        }
        guard !remoteSetupIsBusy else { return }

        remoteSetupIsBusy = true
        remoteConnectionState = .connecting
        let configuration = remoteConfiguration
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    try SSHRemoteInstaller.removeStaleSocket(configuration)
                }.value
                guard let self else { return }
                guard self.remoteConnectionDesired else {
                    self.remoteSetupIsBusy = false
                    self.remoteConnectionState = .disconnected
                    return
                }
                try self.startRemoteTransport(configuration)
                try? await Task.sleep(for: .milliseconds(700))
                guard self.remoteConnectionDesired else {
                    self.stopRemoteTransport()
                    self.remoteSetupIsBusy = false
                    self.remoteConnectionState = .disconnected
                    return
                }
                guard self.remoteTunnel.isRunning else {
                    self.remoteSetupIsBusy = false
                    if !self.remoteConnectionState.isFailed {
                        self.remoteConnectionState = .failed("SSH tunnel closed during startup")
                    }
                    self.scheduleRemoteReconnect()
                    return
                }
                self.remoteSetupIsBusy = false
                self.remoteConnectionState = .connected
                self.statusMessage = "SSH source connected: \(configuration.displayName)."
                self.startRemoteDiscovery(configuration)
            } catch {
                self?.remoteSetupIsBusy = false
                self?.stopRemoteTransport()
                if self?.remoteConnectionDesired == true {
                    self?.remoteConnectionState = .failed(error.localizedDescription)
                    self?.statusMessage = "SSH connection failed: \(error.localizedDescription)"
                    self?.scheduleRemoteReconnect()
                } else {
                    self?.remoteConnectionState = .disconnected
                }
            }
        }
    }

    func disconnectRemote() {
        remoteConnectionDesired = false
        remoteReconnectTask?.cancel()
        remoteReconnectTask = nil
        stopRemoteTransport()
        remoteDiscoveryTask?.cancel()
        remoteDiscoveryTask = nil
        remoteDiscoveryIsBusy = false
        remoteSetupIsBusy = false
        remoteConnectionState = .disconnected
    }

    func refreshRemoteSessions() {
        guard remoteConnectionState.isConnected, !remoteDiscoveryIsBusy else { return }
        let configuration = remoteConfiguration
        Task { [weak self] in
            await self?.performRemoteDiscovery(configuration, announcesResult: true)
        }
    }

    func uninstallRemote() {
        guard !remoteSetupIsBusy else { return }
        remoteSetupIsBusy = true
        disconnectRemote()
        remoteSetupIsBusy = true
        statusMessage = "Restoring the original remote Claude status line…"
        let configuration = remoteConfiguration
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    try SSHRemoteInstaller.uninstall(configuration)
                }.value
                guard let self else { return }
                self.remoteConfiguration.isInstalled = false
                self.remoteSetupIsBusy = false
                self.statusMessage = "Remote wrapper removed; the original status line was restored."
            } catch {
                self?.remoteSetupIsBusy = false
                self?.remoteConnectionState = .failed(error.localizedDescription)
                self?.statusMessage = "Remote uninstall failed: \(error.localizedDescription)"
            }
        }
    }

    func setIslandExpanded(_ expanded: Bool) {
        guard isIslandExpanded != expanded else { return }
        isIslandExpanded = expanded
    }

    func handleIslandHover(_ hovering: Bool) {
        if ProcessInfo.processInfo.environment["CQI_HOLD_EXPANDED"] == "1" {
            setIslandExpanded(true)
            return
        }

        if hovering {
            hoverCloseTask?.cancel()
            hoverCloseTask = nil
            setIslandExpanded(true)
            return
        }

        guard isIslandExpanded, hoverCloseTask == nil else { return }
        hoverCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            self?.hoverCloseTask = nil
            self?.setIslandExpanded(false)
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            statusMessage = enabled ? "Launch at Login enabled." : "Launch at Login disabled."
        } catch {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            statusMessage = "Launch at Login failed: \(error.localizedDescription)"
        }
    }

    func installStatusLine(preserveExisting: Bool) {
        guard let executableURL else {
            statusMessage = StatusLineInstallerError.executableMissing.localizedDescription
            return
        }
        statusMessage = preserveExisting
            ? "Installing wrapper and preserving your current status line…"
            : "Installing Claude status-line bridge…"
        let installer = statusLineInstaller
        Task { [weak self] in
            do {
                let status = try await Task.detached(priority: .utility) {
                    try installer.install(
                        executableURL: executableURL,
                        preserveExistingStatusLine: preserveExisting
                    )
                }.value
                self?.installationStatus = status
                self?.statusMessage = "Claude status-line bridge connected. Start or resume a Claude turn to populate data."
            } catch {
                self?.statusMessage = "Install failed: \(error.localizedDescription)"
                self?.refreshInstallationStatus(autoRepair: false)
            }
        }
    }

    func repairStatusLine() {
        guard let executableURL else {
            statusMessage = StatusLineInstallerError.executableMissing.localizedDescription
            return
        }
        statusMessage = "Repairing Claude status-line bridge…"
        let installer = statusLineInstaller
        Task { [weak self] in
            do {
                let status = try await Task.detached(priority: .utility) {
                    try installer.repair(executableURL: executableURL)
                }.value
                self?.installationStatus = status
                self?.statusMessage = "Claude status-line bridge repaired."
            } catch {
                self?.statusMessage = "Repair failed: \(error.localizedDescription)"
            }
        }
    }

    func uninstallStatusLine() {
        statusMessage = "Removing Claude status-line bridge…"
        let installer = statusLineInstaller
        Task { [weak self] in
            do {
                let status = try await Task.detached(priority: .utility) {
                    try installer.uninstall()
                }.value
                self?.installationStatus = status
                self?.statusMessage = "Claude status-line bridge removed; previous status line restored."
            } catch {
                self?.statusMessage = "Uninstall failed: \(error.localizedDescription)"
            }
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func startSnapshotMonitoring() {
        guard monitorTask == nil else { return }
        let store = snapshotStore
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let values = try await Task.detached(priority: .utility) {
                        try store.loadSnapshots(newerThan: Self.sessionRetention)
                    }.value
                    guard !Task.isCancelled else { return }
                    if self?.snapshots != values {
                        self?.snapshots = values
                        if !values.isEmpty {
                            self?.statusMessage = "Receiving Claude status-line data from \(values.count) session\(values.count == 1 ? "" : "s")."
                        }
                    }
                } catch {
                    self?.statusMessage = "Snapshot read failed: \(error.localizedDescription)"
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshSnapshots() {
        let store = snapshotStore
        Task { [weak self] in
            do {
                let values = try await Task.detached(priority: .utility) {
                    try store.pruneSnapshots(olderThan: Self.sessionRetention)
                    return try store.loadSnapshots(newerThan: Self.sessionRetention)
                }.value
                self?.snapshots = values
            } catch {
                self?.statusMessage = "Snapshot read failed: \(error.localizedDescription)"
            }
        }
    }

    private func refreshInstallationStatus(autoRepair: Bool) {
        let installer = statusLineInstaller
        let executableURL = executableURL
        Task { [weak self] in
            do {
                var status = try await Task.detached(priority: .utility) {
                    try installer.status()
                }.value
                self?.installationStatus = status

                guard ProcessInfo.processInfo.environment["CQI_DISABLE_AUTO_INSTALL"] != "1",
                      let executableURL else { return }

                if status.isConfigured && !status.isHealthy && autoRepair {
                    status = try await Task.detached(priority: .utility) {
                        try installer.repair(executableURL: executableURL)
                    }.value
                    self?.installationStatus = status
                    self?.statusMessage = "Claude status-line bridge repaired."
                } else if !status.isConfigured && !status.hasConflict {
                    self?.statusMessage = "Open Settings and choose Install to connect Claude Code."
                } else if status.hasConflict {
                    self?.statusMessage = "Open Settings to preserve and wrap your current Claude status line."
                }
            } catch {
                self?.statusMessage = "Status-line check failed: \(error.localizedDescription)"
            }
        }
    }

    private func persistDisplayPreferences() {
        guard let data = try? JSONEncoder().encode(displayPreferences) else { return }
        defaults.set(data, forKey: Self.displayPreferencesDefaultsKey)
    }

    private func persistRemoteConfiguration() {
        guard let data = try? JSONEncoder().encode(remoteConfiguration) else { return }
        defaults.set(data, forKey: Self.remoteConfigurationDefaultsKey)
    }

    private func updateRemoteConnectionForSelection() {
        guard remoteConfiguration.isInstalled else {
            remoteConnectionDesired = false
            return
        }
        if preferredSourceID == ClaudeSnapshotSource.local.id {
            disconnectRemote()
        } else {
            remoteConnectionDesired = true
            if !remoteTunnel.isRunning, !remoteSetupIsBusy {
                connectRemote()
            }
        }
    }

    private func startRemoteTransport(_ configuration: RemoteClaudeConfiguration) throws {
        stopRemoteTransport()

        let server = RemotePayloadServer(
            socketPath: RemoteClaudeConfiguration.localSocketPath,
            source: configuration.source,
            snapshotStore: snapshotStore,
            allowedProjectPaths: [],
            onIngest: { [weak self] in
                DispatchQueue.main.async {
                    self?.refreshSnapshots()
                }
            },
            onError: { [weak self] message in
                DispatchQueue.main.async {
                    self?.statusMessage = message
                }
            }
        )
        try server.start()
        remotePayloadServer = server

        do {
            try remoteTunnel.connect(configuration: configuration) { [weak self] message in
                guard let self else { return }
                self.remoteDiscoveryTask?.cancel()
                self.remoteDiscoveryTask = nil
                self.remoteDiscoveryIsBusy = false
                self.remotePayloadServer?.stop()
                self.remotePayloadServer = nil
                self.remoteSetupIsBusy = false
                self.remoteConnectionState = .failed(message ?? "SSH tunnel closed")
                self.statusMessage = message.map { "SSH tunnel closed: \($0)" }
                    ?? "SSH tunnel closed."
                self.scheduleRemoteReconnect()
            }
        } catch {
            server.stop()
            remotePayloadServer = nil
            throw error
        }
    }

    private func stopRemoteTransport() {
        remoteTunnel.disconnect()
        remotePayloadServer?.stop()
        remotePayloadServer = nil
    }

    private func scheduleRemoteReconnect() {
        remoteReconnectTask?.cancel()
        guard remoteConnectionDesired,
              remoteConfiguration.isInstalled,
              preferredSourceID != ClaudeSnapshotSource.local.id else {
            return
        }

        statusMessage = "SSH disconnected. Retrying in 8 seconds…"
        remoteReconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.remoteConnectionDesired else { return }
            self.remoteReconnectTask = nil
            self.connectRemote()
        }
    }

    private func startRemoteDiscovery(_ configuration: RemoteClaudeConfiguration) {
        remoteDiscoveryTask?.cancel()
        remoteDiscoveryTask = Task { [weak self] in
            await self?.performRemoteDiscovery(configuration, announcesResult: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.performRemoteDiscovery(configuration, announcesResult: false)
            }
        }
    }

    private func performRemoteDiscovery(
        _ configuration: RemoteClaudeConfiguration,
        announcesResult: Bool
    ) async {
        guard !remoteDiscoveryIsBusy else { return }
        remoteDiscoveryIsBusy = true
        defer { remoteDiscoveryIsBusy = false }
        let store = snapshotStore
        do {
            let discovered = try await Task.detached(priority: .utility) {
                try RemoteSessionDiscovery.discover(configuration, includesAllProjects: true)
            }.value
            try await Task.detached(priority: .utility) {
                for snapshot in discovered {
                    try store.mergeDiscovered(snapshot)
                }
            }.value
            refreshSnapshots()
            if announcesResult {
                if discovered.isEmpty {
                    statusMessage = configuration.projectPaths.isEmpty
                        ? "SSH connected. Add a project folder to discover existing sessions."
                        : "SSH connected, but no Claude transcripts were found in the selected folders."
                } else {
                    statusMessage = "Loaded \(discovered.count) remote session\(discovered.count == 1 ? "" : "s"). Live status-line updates provide exact quota and context."
                }
            }
        } catch {
            if announcesResult {
                statusMessage = "Remote session discovery failed: \(error.localizedDescription)"
            }
        }
    }

    private func startLocalDiscovery() {
        guard ProcessInfo.processInfo.environment["CQI_DISABLE_DISCOVERY"] != "1" else {
            return
        }
        localDiscoveryTask?.cancel()
        localDiscoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let store = self.snapshotStore
                do {
                    let discovered = try await Task.detached(priority: .utility) {
                        try LocalSessionDiscovery.discover()
                    }.value
                    try await Task.detached(priority: .utility) {
                        for snapshot in discovered {
                            try store.mergeDiscovered(snapshot)
                        }
                    }.value
                    self.refreshSnapshots()
                } catch {
                    if self.preferredSourceID == ClaudeSnapshotSource.local.id {
                        self.statusMessage = "Local session discovery failed: \(error.localizedDescription)"
                    }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
