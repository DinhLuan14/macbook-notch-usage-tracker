# Privacy

Claude Quota Island is local-first. It has no account system, analytics,
telemetry, advertising, hosted API, or automatic update request.

## Local data read

The app may read:

- `~/.claude/settings.json` to report and manage the opt-in status-line bridge;
- recent `~/.claude/projects/**/*.jsonl` files to recover session metadata;
- status-line JSON sent by Claude Code;
- macOS screen safe-area information for notch placement.

Transcript discovery reads only enough recent JSONL data to derive session ID,
working directory, model, and aggregate token usage. Prompt and response text is
not stored in the app cache or displayed by the app.

## Local data written

Snapshots are stored under:

```text
~/Library/Caches/ClaudeQuotaIsland/sessions/
```

A snapshot can contain:

- session and source identifiers;
- project, working-directory, and transcript paths;
- model and reasoning effort;
- context/token counts;
- quota percentages and reset timestamps;
- last update time.

Snapshots are retained for up to 30 days and use owner-only directory/file
permissions. Paths and session IDs can still be sensitive; do not attach cache
files to public issues.

Display preferences, selected project/session IDs, Launch at Login state, and
SSH configuration are stored by macOS UserDefaults. SSH configuration includes
host, user, port, display label, and selected paths. It does not include a
password or private key.

## Claude settings changes

Only after the user chooses Install, Repair, or Uninstall, the app may update:

```text
~/.claude/settings.json
~/.claude-quota-island/
```

Backups are created before settings changes. Existing custom status lines are
not overwritten automatically.

## SSH data flow

When SSH is enabled:

1. `/usr/bin/ssh` authenticates with the user's existing configuration.
2. A reverse Unix-socket tunnel carries status-line JSON to the Mac.
3. The Mac stores the same metadata fields described above.
4. Remote discovery reads transcript metadata and returns a bounded JSON list.

No Claude credentials or full conversation content are copied. The configured
server naturally sees the user's SSH connection.

## Network access

The app itself opens no internet analytics or backend connection. Network
activity occurs only when:

- the user configures and connects an SSH source; or
- the user clicks a documentation/source link.

## Delete local data

Use Settings to uninstall wrappers first. Then quit the app and remove:

```text
~/Library/Caches/ClaudeQuotaIsland/
~/.claude-quota-island/
```

Claude settings backups remain next to the relevant settings files so recovery
is still possible.
