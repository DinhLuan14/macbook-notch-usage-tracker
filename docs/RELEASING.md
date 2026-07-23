# Release checklist

## 1. Prepare

- Update `CFBundleShortVersionString` and `CFBundleVersion` in
  `config/Info.plist`.
- Update user-facing documentation and `NOTICE.md` if attribution changes.
- Confirm the working tree contains no cache, app bundle, archive, log, local
  settings, certificate, or key.
- Run a secret scanner such as `gitleaks` when available.

## 2. Verify

```bash
swift run ClaudeQuotaIslandChecks
swift build
swift build -c release
zsh scripts/build-app.sh
git diff --check
```

Manually verify:

- compact and expanded notch layout;
- local install, wrapper preservation, repair, and uninstall;
- SSH install/connect/discovery/uninstall on a disposable test account;
- Launch at Login from an installed app bundle;
- About and license notices.

## 3. Sign and notarize binary releases

Build with a Developer ID identity:

```bash
CQI_CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  zsh scripts/build-app.sh
```

Submit the app or a temporary ZIP with `xcrun notarytool`, staple the accepted
ticket with `xcrun stapler`, and verify:

```bash
codesign --verify --deep --strict --verbose=2 \
  "build/Claude Quota Island.app"
spctl --assess --type execute --verbose=2 \
  "build/Claude Quota Island.app"
```

Apple signing credentials must remain in Keychain or CI secrets and must never
be committed.

## 4. Package

After stapling:

```bash
zsh scripts/package-release.sh
```

Upload both the ZIP and `.sha256` file to the GitHub Release. Publish the
corresponding source commit or source archive under GPLv3.

## 5. Public-history safety

Before the first push to an empty public repository, use a clean root commit if
private hosts, usernames, paths, or corporate email addresses appeared in local
development history. Do not push private development branches or tags.
