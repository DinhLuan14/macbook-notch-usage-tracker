# MacBook Notch Usage Tracker

<p align="center">
  <strong>Claude Code quota and context, kept quietly beside the MacBook notch.</strong>
  <br>
  Native SwiftUI + AppKit. Local-first. No account, telemetry, or cloud service.
</p>

<p align="center">
  <a href="LICENSE"><img alt="GPL v3" src="https://img.shields.io/badge/license-GPLv3-green"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-orange">
</p>

The app is currently named **Claude Quota Island**. Its compact view shows
account quota on the left and the selected Claude Code session on the right:

```text
5h 31% 4h34 | 7d 34%  [physical notch]  Opus 4.8 | 63%
```

Hover the island for effort, reset details, token count, and project/session
selection. The compact width is measured from the current content and the
physical notch safe areas reported by AppKit.

If you only want quota tracking, choose **Appearance → Right side → Claude
only**. The right side then stays compact and shows `Claude` without project,
model, context, or conversation controls.

Usage colors are mint below 50%, orange from 50–79%, and red from 80%.

## Why this exists

This repository intentionally keeps a small scope:

- Claude Code 5-hour and 7-day quota windows.
- Current model, effort, context percentage, and token count.
- Local Claude sessions plus one optional SSH server.
- Recent-project and conversation selection.
- Four display styles and automatic physical-notch sizing.

It does **not** include analytics, a hosted backend, Claude credentials,
terminal automation, notifications, or support for unrelated coding agents.

## Requirements

- macOS 14 or newer.
- A MacBook notch is recommended; other screens use a top-center fallback.
- Claude Code installed locally, remotely through SSH, or both.
- Swift 6.2 toolchain to build from source.
- For SSH: key/agent authentication and Python 3 on the server.

## Install from source

```bash
git clone https://github.com/DinhLuan14/macbook-notch-usage-tracker.git
cd macbook-notch-usage-tracker
zsh scripts/install-local.sh
```

This builds an ad-hoc signed local app at:

```text
~/Applications/Claude Quota Island.app
```

Open Settings from the notch context menu, then:

1. In **General**, choose **Install** under Claude Code.
2. Start or resume one Claude Code turn.
3. In **Appearance**, choose the compact style you prefer.
4. Optionally configure an SSH source in the **SSH** tab.

The first launch does not modify Claude Code automatically. If Claude already
has a custom status line, the app offers **Install as Wrapper** and preserves
the original command.

See [Installation and build guide](docs/INSTALL.md) for Xcode, command-line,
upgrade, uninstall, signing, and Gatekeeper details.

## SSH

The SSH integration uses `/usr/bin/ssh`, your existing key or agent, and normal
`known_hosts` verification. It does not store a password or private key.

Before using the app, verify that non-interactive SSH works:

```bash
ssh -p 22 alice@dev.example.com true
```

Then enter the same host, user, port, and one or more absolute project paths in
Settings → SSH. Read [SSH setup](docs/SSH.md) before installing because the
operation creates reversible status-line wrappers on the server.

## Privacy and security

- Session processing happens locally.
- Only session metadata is cached; prompt and response text is not copied.
- Cache directories use owner-only permissions.
- SSH status payloads travel through an encrypted reverse Unix-socket tunnel.
- SSH host, user, and selected folder paths are stored in macOS UserDefaults;
  they are configuration, not credentials.
- No telemetry or automatic update network request is present.

Read [Privacy](docs/PRIVACY.md) and [Security](SECURITY.md) for the exact files,
retention, threat model, and reporting process.

## Development

```bash
swift run ClaudeQuotaIslandChecks
swift build
swift build -c release
zsh scripts/build-app.sh
```

Useful commands:

- `zsh scripts/launch-dev-app.sh` — build and launch a development app bundle.
- `zsh scripts/package-release.sh` — create a ZIP and SHA-256 checksum in
  `dist/`.
- `swift run ClaudeQuotaIslandApp` — run the executable without an app bundle;
  Launch at Login is unavailable in this mode.

The package has no third-party runtime dependencies. Architecture and data-flow
notes are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Known limitations

- Claude quota appears only after Claude Code emits a status-line payload that
  includes rate-limit fields. A newly installed wrapper may show `…` until the
  next Claude response.
- Transcript discovery can recover project/model/token metadata, but exact live
  context and account quota require the status-line bridge.
- The release script creates an ad-hoc signed archive by default. Public binary
  distribution should use a Developer ID signature and Apple notarization.
- SSH is intentionally non-interactive (`BatchMode=yes`); password prompts and
  first-time host-key prompts are not handled by the app.
- The app retries an installed SSH source after transient tunnel failures.

## Attribution and license

The notch interaction and local-first direction were inspired by
[Open Island](https://github.com/Octane0411/open-vibe-island), which is licensed
under GNU GPL v3. This project is a focused and substantially modified Claude
quota tracker, is not endorsed by Open Island, and remains licensed under
**GNU GPL v3**.

See [NOTICE.md](NOTICE.md) for attribution and the modification notice. The
complete license is in [LICENSE](LICENSE).
