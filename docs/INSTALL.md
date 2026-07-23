# Installation and build guide

## Requirements

- macOS 14 or newer.
- Swift 6.2 command-line tools or a compatible Xcode toolchain.
- Claude Code for the local bridge.
- Optional SSH server with Python 3 for remote sessions.

Check the toolchain:

```bash
swift --version
```

## Build and install locally

```bash
git clone https://github.com/DinhLuan14/macbook-notch-usage-tracker.git
cd macbook-notch-usage-tracker
zsh scripts/install-local.sh
```

The script performs a release build, creates an ad-hoc code signature, installs
the app into `~/Applications`, and launches it.

Preferences from pre-release builds using the former development bundle ID are
migrated once on first launch.

To build without installing:

```bash
zsh scripts/build-app.sh
```

Output:

```text
build/Claude Quota Island.app
```

To work in Xcode:

```bash
open Package.swift
```

Select the `ClaudeQuotaIslandApp` executable scheme. Running the bare
executable is useful for development, but app-bundle features such as Launch at
Login require `scripts/build-app.sh` or `scripts/install-local.sh`.

## First-run setup

1. Open Settings from the notch context menu or the app menu.
2. In **General**, review the status-line bridge state.
3. Choose **Install**.
4. If a custom Claude status line is detected, choose **Install as Wrapper**
   only after reviewing that behavior.
5. Start or resume a Claude Code turn.

Installation is opt-in. The app does not change Claude settings merely because
it was launched.

The local installer:

- backs up `~/.claude/settings.json`;
- installs owner-only helpers under `~/.claude-quota-island/bin/`;
- stores snapshots under
  `~/Library/Caches/ClaudeQuotaIsland/sessions/`;
- preserves a previous custom status line when wrapper mode is selected.

## Upgrade

Pull the newest source and rerun the installer:

```bash
git pull --ff-only
zsh scripts/install-local.sh
```

Open Settings → General and choose **Repair** if the status-line helper reports
an older or missing executable.

## Uninstall

Before deleting the app:

1. Open Settings → General → **Uninstall** to restore the previous local Claude
   status line.
2. If SSH was configured, open Settings → SSH → **Uninstall** while the server
   is reachable.
3. Disable Launch at Login.
4. Quit the app.

Then remove the app in Finder. Optional local data can be removed manually:

```text
~/Library/Caches/ClaudeQuotaIsland/
~/.claude-quota-island/
```

Claude settings backups are intentionally retained next to their original
settings files.

## Gatekeeper, signing, and notarization

`scripts/build-app.sh` uses an ad-hoc signature by default. This is appropriate
for a local source build but not a polished public binary release.

To sign with a Developer ID certificate:

```bash
CQI_CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  zsh scripts/build-app.sh
```

Public binary releases should also be submitted to Apple notarization and
stapled before packaging. See [RELEASING.md](RELEASING.md).
