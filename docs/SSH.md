# SSH setup

SSH support is optional. Claude Code remains authenticated independently on the
server; this app does not copy Claude credentials.

## Prerequisites

- Key-based or SSH-agent authentication.
- The server host key already trusted in `~/.ssh/known_hosts`.
- Python 3 on the server.
- Claude Code installed for the remote user.
- One or more absolute remote project paths.

Verify the connection manually first:

```bash
ssh -p 22 alice@dev.example.com true
```

The app uses `BatchMode=yes`, so it will not display a password, passphrase, or
first-time host-key prompt.

## Configure the app

1. Open Settings → SSH.
2. Enter a display name, host or SSH config alias, user, and port.
3. Add absolute project paths such as `/srv/projects/example`.
4. Choose **Install & Connect**.
5. Restart active Claude Code sessions on the server.

Use **Repair & Connect** after changing the selected project paths or updating
the local app.

## What installation changes

The remote installer creates backups before updating:

- `~/.claude/settings.json`;
- `<project>/.claude/settings.json` for each selected project.

Managed files are placed under:

```text
~/.claude-quota-island/
```

The server-side reverse Unix socket is placed in an owner-only directory under
`/tmp`. Its Mac-side endpoint lives in the owner-only app cache directory. The
wrapper sends Claude's status-line JSON through the encrypted SSH connection.
An existing status-line command is retained as a delegate and remains the
terminal renderer.

The installer does not patch the original status-line script in place. Existing
Claude sessions must be restarted to reload changed settings.

## Data copied to the Mac

Live payloads can contain:

- session ID and project path;
- model and reasoning effort;
- context/token counts;
- 5-hour and 7-day quota values and reset timestamps.

Recent-session discovery reads remote transcript metadata but does not copy
prompt or response text. See [PRIVACY.md](PRIVACY.md).

## Advanced CLI setup

After building the app, the executable supports the same setup without opening
Settings:

```bash
build/Claude\ Quota\ Island.app/Contents/MacOS/ClaudeQuotaIslandApp \
  --remote-install \
  --host dev.example.com \
  --user alice \
  --port 22 \
  --label "Development" \
  --folder /srv/projects/example
```

Discovery:

```bash
build/Claude\ Quota\ Island.app/Contents/MacOS/ClaudeQuotaIslandApp \
  --remote-discover --all-projects
```

Uninstall:

```bash
build/Claude\ Quota\ Island.app/Contents/MacOS/ClaudeQuotaIslandApp \
  --remote-uninstall
```

CLI configuration is stored in the same macOS UserDefaults domain as the app.

## Troubleshooting

- **Permission denied** — confirm the key or agent works in Terminal.
- **Host key verification failed** — connect manually and verify the host key;
  do not disable `StrictHostKeyChecking`.
- **Connected but no quota** — restart Claude Code and complete one response.
- **Sessions but no context** — transcript discovery found metadata; a live
  status-line payload has not arrived yet.
- **Project missing** — use an absolute path that exists for the remote user.
