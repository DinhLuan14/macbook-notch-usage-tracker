# Security Policy

## Supported version

Security fixes are currently applied to the latest commit on `main`. There is
not yet a stable long-term-support release line.

## Report a vulnerability

Please use GitHub's private vulnerability reporting flow:

<https://github.com/DinhLuan14/macbook-notch-usage-tracker/security/advisories/new>

Do not include credentials, private keys, Claude transcripts, company hostnames,
or other sensitive production data in a public issue. A minimal synthetic
reproduction is preferred.

## Security boundaries

- The app never reads or stores a Claude password, API token, SSH password, or
  SSH private key.
- SSH authentication and host verification are delegated to `/usr/bin/ssh`.
- SSH commands run with `BatchMode=yes`; the app cannot answer password or
  host-key prompts.
- Local cache directories and snapshot files are restricted to the current
  user.
- The local Unix socket accepts owner-only connections and limits status
  payloads to 2 MiB.
- Status-line installation is explicit and creates backups before changing
  Claude settings.
- Existing custom status-line commands are preserved only when the user chooses
  **Install as Wrapper**.

## User responsibilities

- Verify the SSH host manually before configuring it in the app.
- Protect the macOS account and SSH agent.
- Review selected remote project paths before installing wrappers.
- Do not publish cache files, UserDefaults exports, Claude settings backups, or
  server installation directories.

See [docs/PRIVACY.md](docs/PRIVACY.md) for the stored-data inventory.
