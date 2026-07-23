import ClaudeQuotaIslandCore
import Foundation

enum RemoteSessionDiscovery {
    private struct Record: Decodable {
        var sessionID: String
        var sessionName: String?
        var workingDirectory: String?
        var projectDirectory: String?
        var transcriptPath: String?
        var modelID: String?
        var modelDisplayName: String?
        var totalInputTokens: Int?
        var totalOutputTokens: Int?
        var updatedAt: Double
    }

    static func discover(
        _ configuration: RemoteClaudeConfiguration,
        includesAllProjects: Bool = false
    ) throws -> [ClaudeSessionSnapshot] {
        guard includesAllProjects || !configuration.projectPaths.isEmpty else { return [] }
        let result = try SSHCommandRunner.run(
            configuration: configuration,
            remoteArguments: [
                "python3",
                "-",
                includesAllProjects ? "--all" : "--selected",
            ] + configuration.projectPaths,
            input: Data(program.utf8)
        )
        guard let data = result.output.data(using: .utf8) else {
            throw SSHRemoteError.commandFailed("Remote session discovery returned invalid text.")
        }
        do {
            return try JSONDecoder().decode([Record].self, from: data).map { record in
                ClaudeSessionSnapshot(
                    sessionID: record.sessionID,
                    sourceID: configuration.source.id,
                    sourceLabel: configuration.source.label,
                    sourceIsRemote: true,
                    sessionName: record.sessionName,
                    workingDirectory: record.workingDirectory,
                    projectDirectory: record.projectDirectory,
                    transcriptPath: record.transcriptPath,
                    modelID: record.modelID,
                    modelDisplayName: record.modelDisplayName,
                    totalInputTokens: record.totalInputTokens,
                    totalOutputTokens: record.totalOutputTokens,
                    updatedAt: Date(timeIntervalSince1970: record.updatedAt)
                )
            }
        } catch {
            let diagnostic = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHRemoteError.commandFailed(
                diagnostic.isEmpty
                    ? "Could not decode sessions returned by the SSH server."
                    : diagnostic
            )
        }
    }

    private static let program = #"""
import collections
import json
import os
import re
import sys
import time

home = os.path.expanduser("~")
mode = sys.argv[1] if len(sys.argv) > 1 else "--selected"
project_paths = [os.path.normpath(path) for path in sys.argv[2:]]
cutoff = time.time() - (30 * 24 * 60 * 60)

def display_model(model_id):
    if not model_id:
        return None
    value = model_id.removeprefix("claude-")
    parts = value.split("-")
    family = parts[0].capitalize() if parts else "Claude"
    version_parts = [part for part in parts[1:] if part.isdigit()]
    version = ".".join(version_parts[:2])
    return (family + (" " + version if version else "")).strip()

def recent_records(path, maximum=1000):
    values = collections.deque(maxlen=maximum)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                values.append(line)
    except OSError:
        return []
    return values

projects_root = os.path.join(home, ".claude", "projects")
directories = []
if mode == "--all" and os.path.isdir(projects_root):
    values = []
    for name in os.listdir(projects_root):
        path = os.path.join(projects_root, name)
        if not os.path.isdir(path):
            continue
        newest = 0
        try:
            for child in os.listdir(path):
                if child.endswith(".jsonl"):
                    newest = max(newest, os.path.getmtime(os.path.join(path, child)))
        except OSError:
            continue
        if newest >= cutoff:
            values.append((newest, None, path))
    values.sort(reverse=True)
    directories = [(configured, path) for _, configured, path in values[:24]]
else:
    for project_path in project_paths:
        encoded = re.sub(r"[^A-Za-z0-9]", "-", project_path)
        transcript_directory = os.path.join(projects_root, encoded)
        if os.path.isdir(transcript_directory):
            directories.append((project_path, transcript_directory))

result = []
for configured_project, transcript_directory in directories:
    candidates = []
    for name in os.listdir(transcript_directory):
        if not name.endswith(".jsonl"):
            continue
        path = os.path.join(transcript_directory, name)
        try:
            modified = os.path.getmtime(path)
        except OSError:
            continue
        if modified >= cutoff:
            candidates.append((modified, path))
    candidates.sort(reverse=True)

    directory_result = []
    directory_cwds = []
    maximum_sessions = 12 if mode == "--all" else 50
    for modified, transcript_path in candidates[:maximum_sessions]:
        session_id = os.path.splitext(os.path.basename(transcript_path))[0]
        cwd = None
        model_id = None
        total_input = None
        total_output = None
        for line in reversed(recent_records(transcript_path)):
            try:
                event = json.loads(line)
            except Exception:
                continue
            if cwd is None and isinstance(event.get("cwd"), str):
                cwd = event["cwd"]
            if isinstance(event.get("sessionId"), str):
                session_id = event["sessionId"]
            message = event.get("message")
            if event.get("type") != "assistant" or not isinstance(message, dict):
                continue
            raw_model = message.get("model")
            if isinstance(raw_model, str) and not raw_model.startswith("<"):
                model_id = raw_model
            usage = message.get("usage")
            if model_id and isinstance(usage, dict):
                values = [
                    usage.get("input_tokens"),
                    usage.get("cache_creation_input_tokens"),
                    usage.get("cache_read_input_tokens"),
                ]
                numeric = [value for value in values if isinstance(value, (int, float))]
                if numeric:
                    total_input = int(sum(numeric))
                if isinstance(usage.get("output_tokens"), (int, float)):
                    total_output = int(usage["output_tokens"])
            if model_id:
                break
        if cwd is None:
            cwd = configured_project
        if cwd:
            directory_cwds.append(cwd)
        directory_result.append({
            "sessionID": session_id,
            "workingDirectory": cwd,
            "transcriptPath": transcript_path,
            "modelID": model_id,
            "modelDisplayName": display_model(model_id),
            "totalInputTokens": total_input,
            "totalOutputTokens": total_output,
            "updatedAt": modified,
        })

    project_directory = configured_project
    if project_directory is None and directory_cwds:
        try:
            project_directory = os.path.commonpath(directory_cwds)
        except ValueError:
            project_directory = directory_cwds[0]
    for item in directory_result:
        resolved_project = project_directory or item.get("workingDirectory")
        folder_name = (
            os.path.basename(resolved_project.rstrip(os.sep))
            if resolved_project else "Project"
        )
        item["projectDirectory"] = resolved_project
        item["sessionName"] = folder_name + " · " + item["sessionID"][:8]
        result.append(item)

result.sort(key=lambda item: item["updatedAt"], reverse=True)
print(json.dumps(result[:200], separators=(",", ":")))
"""#
}
