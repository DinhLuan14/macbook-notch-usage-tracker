import ClaudeQuotaIslandCore
import Foundation

struct SSHCommandResult: Sendable {
    var output: String
    var errorOutput: String
}

enum SSHRemoteError: LocalizedError {
    case invalidConfiguration
    case commandFailed(String)
    case tunnelLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Enter a valid SSH host, user, and port."
        case let .commandFailed(message):
            message
        case let .tunnelLaunchFailed(message):
            "SSH tunnel failed: \(message)"
        }
    }
}

enum SSHRemoteInstaller {
    private struct InstallResponse: Decodable {
        var installed: Bool
        var projects: [String]
        var missing: [String]
    }

    static func install(_ configuration: RemoteClaudeConfiguration) throws {
        guard configuration.isValid else { throw SSHRemoteError.invalidConfiguration }
        let result = try SSHCommandRunner.run(
            configuration: configuration,
            remoteArguments: [
                "python3",
                "-",
                configuration.remoteSocketDirectory,
                configuration.clientID,
            ] + configuration.projectPaths,
            input: Data(installProgram.utf8)
        )
        guard let data = result.output.data(using: .utf8),
              let response = try? JSONDecoder().decode(InstallResponse.self, from: data) else {
            throw SSHRemoteError.commandFailed(
                result.errorOutput.isEmpty ? "Remote installer returned an unexpected response." : result.errorOutput
            )
        }
        if !response.missing.isEmpty {
            throw SSHRemoteError.commandFailed(
                "Remote project folder not found: \(response.missing.joined(separator: ", "))"
            )
        }
        guard response.installed else {
            throw SSHRemoteError.commandFailed("Remote installer did not complete.")
        }
    }

    static func uninstall(_ configuration: RemoteClaudeConfiguration) throws {
        guard configuration.isValid else { throw SSHRemoteError.invalidConfiguration }
        let result = try SSHCommandRunner.run(
            configuration: configuration,
            remoteArguments: [
                "python3",
                "-",
                configuration.remoteSocketPath,
                configuration.clientID,
            ],
            input: Data(uninstallProgram.utf8)
        )
        guard result.output.contains("\"uninstalled\": true") else {
            throw SSHRemoteError.commandFailed(
                result.errorOutput.isEmpty ? "Remote uninstall returned an unexpected response." : result.errorOutput
            )
        }
    }

    static func removeStaleSocket(_ configuration: RemoteClaudeConfiguration) throws {
        let program = """
        import os, sys
        path = sys.argv[1]
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        """
        _ = try SSHCommandRunner.run(
            configuration: configuration,
            remoteArguments: ["python3", "-", configuration.remoteSocketPath],
            input: Data(program.utf8)
        )
    }

    private static let installProgram = #"""
import datetime
import hashlib
import json
import os
import shutil
import sys

socket_directory = sys.argv[1]
client_id = sys.argv[2]
project_paths = [os.path.normpath(path) for path in sys.argv[3:]]
missing_projects = [path for path in project_paths if not os.path.isdir(path)]
if missing_projects:
    print(json.dumps({
        "installed": False,
        "projects": [],
        "missing": missing_projects,
    }))
    sys.exit(0)
home = os.path.expanduser("~")
claude_dir = os.path.join(home, ".claude")
settings_path = os.path.join(claude_dir, "settings.json")
root_dir = os.path.join(home, ".claude-quota-island")
managed_dir = os.path.join(root_dir, "bin")
projects_dir = os.path.join(root_dir, "projects")
clients_dir = os.path.join(root_dir, "clients")
registry_path = os.path.join(root_dir, "projects.json")
relay_path = os.path.join(managed_dir, "statusline-relay.py")
wrapper_path = os.path.join(managed_dir, "statusline")
delegate_path = os.path.join(managed_dir, "statusline-delegate")
legacy_wrapper_path = os.path.join(managed_dir, "remote-statusline")
legacy_delegate_path = os.path.join(managed_dir, "remote-statusline-delegate")
original_key = "_claudeQuotaIslandRemoteOriginalStatusLine"

os.makedirs(claude_dir, exist_ok=True)
for private_directory in (root_dir, managed_dir, projects_dir, clients_dir, socket_directory):
    os.makedirs(private_directory, mode=0o700, exist_ok=True)
    os.chmod(private_directory, 0o700)

def read_settings(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("Claude settings must contain a JSON object: " + path)
    return value

def backup(path):
    if os.path.exists(path):
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup_path = path + ".cqi-backup-" + stamp
        shutil.copy2(path, backup_path)
        os.chmod(backup_path, 0o600)

def write_json(path, value):
    temporary = path + ".cqi-tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)

def write_delegate(path, command):
    if command:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("#!/usr/bin/env bash\n")
            handle.write("# Preserved by Claude Quota Island.\n")
            handle.write(command + "\n")
        os.chmod(path, 0o700)
    else:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

def legacy_original(settings):
    saved = settings.get(original_key)
    saved_command = saved.get("command") if isinstance(saved, dict) else None
    if saved_command and saved_command != legacy_wrapper_path:
        return saved
    if os.path.exists(legacy_delegate_path):
        with open(legacy_delegate_path, "r", encoding="utf-8") as handle:
            commands = [
                line.strip() for line in handle
                if line.strip() and not line.lstrip().startswith("#")
            ]
        if commands:
            return {"type": "command", "command": commands[-1]}
    return None

def install_settings(target_settings, target_wrapper, target_delegate):
    target_directory = os.path.dirname(target_settings)
    os.makedirs(target_directory, mode=0o700, exist_ok=True)
    settings = read_settings(target_settings)
    backup(target_settings)
    current = settings.get("statusLine")
    current_command = current.get("command") if isinstance(current, dict) else None
    if target_settings == settings_path and current_command == legacy_wrapper_path:
        current = legacy_original(settings)
        current_command = current.get("command") if isinstance(current, dict) else None
    if target_settings == settings_path and current_command == target_wrapper:
        saved = settings.get(original_key)
        saved_command = saved.get("command") if isinstance(saved, dict) else None
        if saved_command == legacy_wrapper_path:
            recovered = legacy_original(settings)
            if recovered is not None:
                settings[original_key] = recovered
                write_delegate(target_delegate, recovered.get("command"))
    if current_command != target_wrapper:
        if current is not None:
            settings[original_key] = current
        write_delegate(target_delegate, current_command)
    elif not os.path.exists(target_delegate):
        saved = settings.get(original_key)
        saved_command = saved.get("command") if isinstance(saved, dict) else None
        write_delegate(target_delegate, saved_command)
    settings["statusLine"] = {
        "type": "command",
        "command": target_wrapper,
        "padding": current.get("padding", 2) if isinstance(current, dict) else 2,
        "refreshInterval": 5,
    }
    write_json(target_settings, settings)

relay = '''#!/usr/bin/env python3
import os
import socket
import sys

data = sys.stdin.buffer.read()
if data:
    try:
        names = os.listdir(sys.argv[1])
    except OSError:
        names = []
    for name in names:
        if not name.endswith(".sock"):
            continue
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(0.35)
        try:
            sock.connect(os.path.join(sys.argv[1], name))
            sock.sendall(data)
            sock.shutdown(socket.SHUT_WR)
        except Exception:
            pass
        finally:
            sock.close()
'''
with open(relay_path, "w", encoding="utf-8") as handle:
    handle.write(relay)
os.chmod(relay_path, 0o700)

def write_wrapper(path, delegate):
    wrapper = f'''#!/usr/bin/env bash
# Claude Quota Island SSH bridge. The original status line remains the renderer.
input=$(cat)
printf '%s' "$input" | python3 "{relay_path}" "{socket_directory}" >/dev/null 2>&1 || true
if [ -x "{delegate}" ]; then
  printf '%s' "$input" | "{delegate}"
else
  model=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
  ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
  printf '[%s] %.0f%% context\n' "$model" "$ctx"
fi
exit 0
'''
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(wrapper)
    os.chmod(path, 0o700)

def restore_legacy_loaded_statusline(item):
    if not isinstance(item, dict):
        return
    script_path = item.get("patchedScript")
    backup_path = item.get("scriptBackup")
    if not isinstance(script_path, str) or not isinstance(backup_path, str):
        return
    if not os.path.isfile(script_path) or not os.path.isfile(backup_path):
        return
    try:
        with open(script_path, "r", encoding="utf-8", errors="replace") as handle:
            current = handle.read(512)
    except OSError:
        return
    if "# Claude Quota Island active-session bridge." in current:
        shutil.copy2(backup_path, script_path)

write_wrapper(wrapper_path, delegate_path)
install_settings(settings_path, wrapper_path, delegate_path)

registry = []
if os.path.exists(registry_path):
    try:
        with open(registry_path, "r", encoding="utf-8") as handle:
            value = json.load(handle)
        if isinstance(value, list):
            registry = value
    except Exception:
        registry = []

by_path = {
    item.get("path"): item for item in registry
    if isinstance(item, dict) and isinstance(item.get("path"), str)
}
installed_projects = []
for project_path in project_paths:
    project_key = hashlib.sha256(project_path.encode("utf-8")).hexdigest()[:16]
    project_managed_dir = os.path.join(projects_dir, project_key)
    os.makedirs(project_managed_dir, mode=0o700, exist_ok=True)
    os.chmod(project_managed_dir, 0o700)
    restore_legacy_loaded_statusline(by_path.get(project_path))
    project_settings = os.path.join(project_path, ".claude", "settings.json")
    project_wrapper = os.path.join(project_managed_dir, "statusline")
    project_delegate = os.path.join(project_managed_dir, "statusline-delegate")
    write_wrapper(project_wrapper, project_delegate)
    install_settings(project_settings, project_wrapper, project_delegate)
    project_record = {
        "path": project_path,
        "settings": project_settings,
        "wrapper": project_wrapper,
        "delegate": project_delegate,
    }
    by_path[project_path] = project_record
    installed_projects.append(project_path)

write_json(registry_path, list(by_path.values()))
client_path = os.path.join(clients_dir, client_id + ".json")
write_json(client_path, {
    "clientID": client_id,
    "projectPaths": project_paths,
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
})
for legacy_name in ("remote-statusline", "remote-statusline-relay.py", "remote-statusline-delegate"):
    legacy_path = os.path.join(managed_dir, legacy_name)
    try:
        os.unlink(legacy_path)
    except FileNotFoundError:
        pass
print(json.dumps({
    "installed": True,
    "wrapper": wrapper_path,
    "projects": installed_projects,
    "missing": missing_projects,
}))
"""#

    private static let uninstallProgram = #"""
import datetime
import json
import os
import shutil
import sys

remote_socket = sys.argv[1]
client_id = sys.argv[2]
home = os.path.expanduser("~")
settings_path = os.path.join(home, ".claude", "settings.json")
root_dir = os.path.join(home, ".claude-quota-island")
managed_dir = os.path.join(root_dir, "bin")
clients_dir = os.path.join(root_dir, "clients")
registry_path = os.path.join(root_dir, "projects.json")
wrapper_path = os.path.join(managed_dir, "statusline")
original_key = "_claudeQuotaIslandRemoteOriginalStatusLine"

def restore_settings(path, expected_wrapper):
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as handle:
        settings = json.load(handle)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup_path = path + ".cqi-backup-" + stamp
    shutil.copy2(path, backup_path)
    os.chmod(backup_path, 0o600)
    current = settings.get("statusLine")
    if isinstance(current, dict) and current.get("command") == expected_wrapper:
        if original_key in settings:
            settings["statusLine"] = settings[original_key]
        else:
            settings.pop("statusLine", None)
    settings.pop(original_key, None)
    temporary = path + ".cqi-tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)

def restore_loaded_statusline(item):
    script_path = item.get("patchedScript")
    backup_path = item.get("scriptBackup")
    if not isinstance(script_path, str) or not isinstance(backup_path, str):
        return
    if not os.path.isfile(script_path) or not os.path.isfile(backup_path):
        return
    try:
        with open(script_path, "r", encoding="utf-8", errors="replace") as handle:
            current = handle.read(512)
    except OSError:
        return
    if "# Claude Quota Island active-session bridge." in current:
        shutil.copy2(backup_path, script_path)

try:
    os.unlink(remote_socket)
except FileNotFoundError:
    pass
try:
    os.unlink(os.path.join(clients_dir, client_id + ".json"))
except FileNotFoundError:
    pass

remaining_clients = []
if os.path.isdir(clients_dir):
    remaining_clients = [name for name in os.listdir(clients_dir) if name.endswith(".json")]

restored = False
if not remaining_clients:
    restore_settings(settings_path, wrapper_path)
    registry = []
    if os.path.exists(registry_path):
        try:
            with open(registry_path, "r", encoding="utf-8") as handle:
                value = json.load(handle)
            if isinstance(value, list):
                registry = value
        except Exception:
            registry = []
    for item in registry:
        if not isinstance(item, dict):
            continue
        project_settings = item.get("settings")
        project_wrapper = item.get("wrapper")
        if isinstance(project_settings, str) and isinstance(project_wrapper, str):
            restore_settings(project_settings, project_wrapper)
        restore_loaded_statusline(item)
    for name in ("statusline", "statusline-relay.py", "statusline-delegate"):
        path = os.path.join(managed_dir, name)
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    shutil.rmtree(os.path.join(root_dir, "projects"), ignore_errors=True)
    try:
        os.unlink(registry_path)
    except FileNotFoundError:
        pass
    restored = True

print(json.dumps({
    "uninstalled": True,
    "restored": restored,
    "remainingClients": len(remaining_clients),
}))
"""#
}

enum SSHCommandRunner {
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var standardOutput = Data()
        private var standardError = Data()

        func setStandardOutput(_ data: Data) {
            lock.withLock {
                standardOutput = data
            }
        }

        func setStandardError(_ data: Data) {
            lock.withLock {
                standardError = data
            }
        }

        func values() -> (output: Data, error: Data) {
            lock.withLock {
                (standardOutput, standardError)
            }
        }
    }

    static func run(
        configuration: RemoteClaudeConfiguration,
        remoteArguments: [String],
        input: Data? = nil
    ) throws -> SSHCommandResult {
        guard configuration.isValid else {
            throw SSHRemoteError.invalidConfiguration
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        let remoteCommand = remoteArguments.map(shellQuote).joined(separator: " ")
        process.arguments = baseArguments(configuration: configuration)
            + [configuration.target, remoteCommand]

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let standardInput = Pipe()
        if input != nil {
            process.standardInput = standardInput
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        try process.run()

        // Drain both pipes while SSH is running. Waiting first can deadlock
        // once a large session-discovery response fills a pipe buffer.
        let collector = OutputCollector()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.setStandardOutput(
                standardOutput.fileHandleForReading.readDataToEndOfFile()
            )
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.setStandardError(
                standardError.fileHandleForReading.readDataToEndOfFile()
            )
            readers.leave()
        }

        if let input {
            standardInput.fileHandleForWriting.write(input)
            try? standardInput.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        readers.wait()

        let values = collector.values()
        let output = String(
            data: values.output,
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: values.error,
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw SSHRemoteError.commandFailed(
                errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "SSH exited with status \(process.terminationStatus)."
                    : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return SSHCommandResult(output: output, errorOutput: errorOutput)
    }

    static func baseArguments(configuration: RemoteClaudeConfiguration) -> [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-p", String(configuration.port),
        ]
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

@MainActor
final class SSHRemoteTunnel {
    private var process: Process?
    private var errorPipe: Pipe?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func connect(
        configuration: RemoteClaudeConfiguration,
        onTermination: @escaping @MainActor (String?) -> Void
    ) throws {
        disconnect()
        guard configuration.isValid else { throw SSHRemoteError.invalidConfiguration }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = SSHCommandRunner.baseArguments(configuration: configuration) + [
            "-o", "ExitOnForwardFailure=yes",
            "-N",
            "-R", "\(configuration.remoteSocketPath):\(RemoteClaudeConfiguration.localSocketPath)",
            configuration.target,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        process.terminationHandler = { process in
            let error = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                onTermination(error?.isEmpty == false ? error : nil)
            }
        }

        do {
            try process.run()
        } catch {
            throw SSHRemoteError.tunnelLaunchFailed(error.localizedDescription)
        }
        self.process = process
        self.errorPipe = errorPipe
    }

    func disconnect() {
        guard let process else { return }
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        self.process = nil
        errorPipe = nil
    }
}
