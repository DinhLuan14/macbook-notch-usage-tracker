import Foundation

enum RemoteSetupCommand {
    static func run(
        arguments: [String],
        defaults: UserDefaults = AppModel.runtimeDefaults()
    ) -> Int32 {
        let isUninstall = arguments.contains("--remote-uninstall")
        let isDiscover = arguments.contains("--remote-discover")
        var configuration = storedConfiguration(defaults: defaults) ?? RemoteClaudeConfiguration()

        if let host = value(after: "--host", in: arguments) {
            configuration.host = host
        }
        if let user = value(after: "--user", in: arguments) {
            configuration.user = user
        }
        if let label = value(after: "--label", in: arguments) {
            configuration.label = label
        }
        if let portValue = value(after: "--port", in: arguments), let port = Int(portValue) {
            configuration.port = port
        }
        let folders = values(after: "--folder", in: arguments)
        if !folders.isEmpty {
            configuration.projectPaths = RemoteClaudeConfiguration.normalizedProjectPaths(folders)
        }

        do {
            if isDiscover {
                let sessions = try RemoteSessionDiscovery.discover(
                    configuration,
                    includesAllProjects: arguments.contains("--all-projects")
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(sessions))
                FileHandle.standardOutput.write(Data("\n".utf8))
                return 0
            } else if isUninstall {
                try SSHRemoteInstaller.uninstall(configuration)
                configuration.isInstalled = false
                print("Remote Claude status-line wrapper uninstalled from \(configuration.target).")
            } else {
                try SSHRemoteInstaller.install(configuration)
                configuration.isInstalled = true
                print("Remote Claude status-line wrapper installed on \(configuration.target).")
                print("Remote socket: \(configuration.remoteSocketPath)")
            }
            if let data = try? JSONEncoder().encode(configuration) {
                defaults.set(data, forKey: AppModel.remoteConfigurationDefaultsKey)
            }
            return 0
        } catch {
            FileHandle.standardError.write(
                Data("Remote setup failed: \(error.localizedDescription)\n".utf8)
            )
            return 1
        }
    }

    private static func storedConfiguration(defaults: UserDefaults) -> RemoteClaudeConfiguration? {
        guard let data = defaults.data(forKey: AppModel.remoteConfigurationDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(RemoteClaudeConfiguration.self, from: data)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func values(after flag: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == flag, arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
    }
}
