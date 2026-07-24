# Architecture

The project is a Swift package with three products:

| Product | Role |
| --- | --- |
| `ClaudeQuotaIslandCore` | Payload models, cache, formatting, local installer |
| `ClaudeQuotaIslandApp` | AppKit panel, SwiftUI settings, discovery, SSH |
| `ClaudeQuotaIslandChecks` | Dependency-free executable checks |

## Local flow

```text
Claude Code statusLine JSON
  → managed status-line wrapper
  → app helper --statusline-ingest
  → owner-only snapshot JSON
  → AppModel
  → SwiftUI notch lanes
```

Transcript discovery supplements old sessions with project/model/token
metadata. Live status-line data remains authoritative for exact context and
quota.

Managed local and SSH status-line bridges use Claude Code's
`refreshInterval: 5`, so Claude re-runs the bridge every five seconds in
addition to event-driven status updates. The app checks its snapshot cache every
two seconds, so a newly emitted payload normally reaches the notch within two
seconds. This timer does not call a separate Claude usage API; it only republishes
the latest quota fields Claude provides to the status line.

## SSH flow

```text
Remote Claude Code
  → reversible remote wrapper
  → remote Unix socket
  → encrypted OpenSSH reverse tunnel
  → owner-only local Unix socket in the app cache directory
  → SnapshotStore
```

Swift uses `Process` argument arrays locally. The remote command is emitted as a
single POSIX-shell-quoted command string because OpenSSH executes it through the
remote login shell.

## UI

`NotchPanelController` owns a transparent, non-activating `NSPanel`.
`DisplayGeometry` derives the physical notch gap from AppKit auxiliary safe
areas. Compact wing widths are based on measured content; expanded widths are
stable so hover animation does not reflow controls.

Settings is intentionally split into General, Appearance, SSH, and About rather
than one long dashboard.
