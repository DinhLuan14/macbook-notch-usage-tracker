import ClaudeQuotaIslandCore
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case ssh
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .ssh: "SSH"
        case .about: "About"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section: SettingsSection = .general
    @State private var remoteFolderDraft = ""

    private let sourceURL = URL(
        string: "https://github.com/DinhLuan14/macbook-notch-usage-tracker"
    )!
    private let inspirationURL = URL(
        string: "https://github.com/Octane0411/open-vibe-island"
    )!

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $section) {
                ForEach(SettingsSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            switch section {
            case .general:
                generalPage
            case .appearance:
                appearancePage
            case .ssh:
                sshPage
            case .about:
                aboutPage
            }
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 500, idealHeight: 560)
    }

    private var generalPage: some View {
        settingsPage {
            GroupBox("Claude Code") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle()
                            .fill(model.statusLineIsHealthy ? Color.mint : Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Status-line bridge")
                        Spacer()
                        Text(model.statusLineSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(
                        "Nothing is installed automatically. Choose Install to connect Claude Code. "
                            + "If a custom status line exists, the wrapper preserves and restores it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        if model.installationStatus?.hasConflict == true {
                            Button("Install as Wrapper") {
                                model.installStatusLine(preserveExisting: true)
                            }
                        } else if model.statusLineIsHealthy {
                            Button("Repair", action: model.repairStatusLine)
                            Button("Uninstall", role: .destructive, action: model.uninstallStatusLine)
                        } else {
                            Button("Install") {
                                model.installStatusLine(preserveExisting: false)
                            }
                            if model.installationStatus?.isConfigured == true {
                                Button("Repair", action: model.repairStatusLine)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("What to show") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Data source", selection: $model.preferredSourceID) {
                        Text("Automatic · local + SSH").tag(AppModel.automaticSelectionID)
                        Text(ClaudeSnapshotSource.local.label).tag(ClaudeSnapshotSource.local.id)
                        Text("SSH · \(model.remoteConfiguration.displayName)").tag(model.remoteSourceID)
                    }

                    Picker("Project", selection: projectBinding) {
                        Text("Automatic · monitored folders").tag(AppModel.automaticSelectionID)
                        ForEach(model.recentProjects) { project in
                            Text(projectPickerTitle(project)).tag(project.id)
                        }
                    }

                    Picker("Session", selection: sessionBinding) {
                        Text("Automatic · most recent").tag(AppModel.automaticSelectionID)
                        ForEach(model.recentSnapshots) { session in
                            Text(sessionPickerTitle(session)).tag(session.id)
                        }
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            recentProjectsBox

            GroupBox("System") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .disabled(!LaunchAtLoginService.isAvailable)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            statusFooter
        }
    }

    private var appearancePage: some View {
        settingsPage {
            VStack(spacing: 2) {
                NotchBarPreview(preferences: model.displayPreferences)
                    .frame(maxWidth: .infinity)
                Text("Hover the preview to expand details")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            GroupBox("Notch") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Display style", selection: $model.displayPreferences.style) {
                        ForEach(NotchDisplayStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Picker("Quota value", selection: $model.displayPreferences.quotaMetric) {
                        ForEach(QuotaMetric.allCases) { metric in
                            Text(metric.displayName).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show reset time", isOn: $model.displayPreferences.showsResetTime)
                        .disabled(model.displayPreferences.style == .minimal)
                    Toggle("Show effort", isOn: $model.displayPreferences.showsEffort)
                        .disabled(model.displayPreferences.style == .minimal)
                    Toggle("Show token count", isOn: $model.displayPreferences.showsTokenCount)
                        .disabled(model.displayPreferences.style == .minimal)
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Screen") {
                Picker("Display", selection: $model.preferredDisplayID) {
                    Text("Automatic · prefer built-in notch").tag(AppModel.automaticSelectionID)
                    ForEach(ScreenResolver.availableOptions()) { option in
                        Text(option.hasNotch ? "\(option.name) · notch" : option.name)
                            .tag(option.id)
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sshPage: some View {
        settingsPage {
            GroupBox("SSH Source") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "Uses macOS OpenSSH, your existing SSH agent or key, and known_hosts. "
                            + "The app never stores a password or private key."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Name")
                            TextField("My Server", text: $model.remoteConfiguration.label)
                        }
                        GridRow {
                            Text("Host")
                            TextField("dev.example.com", text: $model.remoteConfiguration.host)
                        }
                        GridRow {
                            Text("User")
                            TextField("alice", text: $model.remoteConfiguration.user)
                        }
                        GridRow {
                            Text("Port")
                            TextField("22", text: remotePortBinding)
                        }
                    }
                    .disabled(model.remoteSetupIsBusy || model.remoteConnectionState.isConnected)

                    Divider()

                    Text("Project folders")
                        .font(.subheadline.weight(.semibold))

                    if model.remoteConfiguration.projectPaths.isEmpty {
                        Text("Add one or more absolute project paths from the SSH server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(model.remoteConfiguration.projectPaths, id: \.self) { path in
                                HStack(spacing: 8) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 8)
                                    Button {
                                        model.removeRemoteProjectPath(path)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove folder")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("/absolute/path/on/server", text: $remoteFolderDraft)
                            .onSubmit(addRemoteFolder)
                        Button("Add", action: addRemoteFolder)
                            .disabled(
                                remoteFolderDraft
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                            )
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(remoteStatusColor)
                            .frame(width: 8, height: 8)
                        Text(model.remoteConnectionState.summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if model.remoteConnectionState.isConnected {
                            Button("Disconnect", action: model.disconnectRemote)
                            Button("Refresh", action: model.refreshRemoteSessions)
                                .disabled(model.remoteDiscoveryIsBusy)
                        } else if model.remoteConfiguration.isInstalled {
                            Button("Connect", action: model.connectRemote)
                                .disabled(model.remoteSetupIsBusy)
                        }
                        Button(
                            model.remoteConfiguration.isInstalled ? "Repair & Connect" : "Install & Connect",
                            action: model.installAndConnectRemote
                        )
                        .disabled(model.remoteSetupIsBusy || !model.remoteConfiguration.isValid)
                        if model.remoteConfiguration.isInstalled {
                            Button("Uninstall", role: .destructive, action: model.uninstallRemote)
                                .disabled(model.remoteSetupIsBusy)
                        }
                    }

                    Text(
                        "Install creates reversible wrappers with backups on the server. "
                            + "Restart active Claude Code sessions after installing or repairing."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            statusFooter
        }
    }

    private var aboutPage: some View {
        settingsPage {
            VStack(spacing: 6) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 36))
                    .foregroundStyle(.cyan)
                Text("Claude Quota Island")
                    .font(.title2.weight(.semibold))
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("A lightweight, local-first Claude Code usage tracker for the MacBook notch.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            GroupBox("Privacy") {
                Text(
                    "No account, telemetry, analytics, or cloud service. The app stores only local "
                        + "session metadata needed for the notch. SSH uses your existing OpenSSH setup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("License and attribution") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Copyright © 2026 DinhLuan14 and contributors.")
                    Text(
                        "Licensed under GNU GPL v3. This program comes with absolutely no warranty. "
                            + "You may redistribute and modify it under the license terms."
                    )
                    Text(
                        "Inspired by Open Island by Octane0411 and contributors. "
                            + "This is a focused, independently modified Claude quota tracker."
                    )
                    HStack {
                        Link("Source code", destination: sourceURL)
                        Link("Open Island", destination: inspirationURL)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Quit App", role: .destructive, action: model.quit)
            }
        }
    }

    private var recentProjectsBox: some View {
        GroupBox("Recent Projects") {
            VStack(spacing: 4) {
                if model.recentProjects.isEmpty {
                    Text("Recent local and SSH Claude projects will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(model.recentProjects.prefix(6))) { project in
                        Button {
                            model.selectProject(project.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: project.source.isRemote ? "globe" : "laptopcomputer")
                                    .frame(width: 18)
                                    .foregroundStyle(
                                        model.selectedProjectID == project.id ? Color.accentColor : .secondary
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(project.name).fontWeight(.medium)
                                        Text(projectSourceLabel(project))
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                    Text(project.path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Text("\(project.sessions.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(
                            model.selectedProjectID == project.id
                                ? Color.accentColor.opacity(0.1)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    }
                    if model.recentProjects.count > 6 {
                        Text("+\(model.recentProjects.count - 6) more projects in the notch menu")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusFooter: some View {
        Text(model.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private var sessionBinding: Binding<String> {
        Binding(
            get: { model.selectedSessionBindingID },
            set: { model.selectedSessionBindingID = $0 }
        )
    }

    private var projectBinding: Binding<String> {
        Binding(
            get: { model.selectedProjectBindingID },
            set: { model.selectedProjectBindingID = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.updateLaunchAtLogin($0) }
        )
    }

    private var remotePortBinding: Binding<String> {
        Binding(
            get: { String(model.remoteConfiguration.port) },
            set: { value in
                if let port = Int(value.filter(\.isNumber)) {
                    model.remoteConfiguration.port = port
                } else if value.isEmpty {
                    model.remoteConfiguration.port = 0
                }
            }
        )
    }

    private var remoteStatusColor: Color {
        switch model.remoteConnectionState {
        case .connected: .mint
        case .connecting: .yellow
        case .disconnected: .secondary
        case .failed: .orange
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func addRemoteFolder() {
        if model.addRemoteProjectPath(remoteFolderDraft) {
            remoteFolderDraft = ""
        }
    }

    private func sessionPickerTitle(_ session: ClaudeSessionSnapshot) -> String {
        "\(session.sessionID.prefix(8)) · \(session.modelDisplayName ?? "Claude")"
    }

    private func projectPickerTitle(_ project: ClaudeRecentProject) -> String {
        "\(project.name) · \(projectSourceLabel(project))"
    }

    private func projectSourceLabel(_ project: ClaudeRecentProject) -> String {
        project.source.isRemote ? "SSH: \(model.remoteConfiguration.host)" : "Local"
    }
}
