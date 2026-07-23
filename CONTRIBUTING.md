# Contributing

Contributions should keep the product lightweight, local-first, and focused on
Claude Code usage in the MacBook notch.

## Before opening a pull request

```bash
swift run ClaudeQuotaIslandChecks
swift build -c release
zsh scripts/build-app.sh
git diff --check
```

Manually check compact/expanded layout when changing SwiftUI or AppKit code.
Use synthetic hosts, usernames, paths, and sessions in tests and documentation.
Never commit Claude transcripts, cache snapshots, settings backups, signing
certificates, keys, company network details, or screenshots containing private
project information.

## Scope

Good changes include:

- reliability and security fixes;
- notch layout and accessibility improvements;
- Claude quota/session parsing;
- reversible local or SSH setup;
- concise documentation and tests.

Large multi-agent dashboards, telemetry, hosted accounts, or unrelated terminal
automation are outside the current scope.

## License

By contributing, you agree that your contribution is licensed under GNU GPL v3
and may be redistributed under the repository's license terms.
