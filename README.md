# Just Play

Just Play is a macOS SwiftUI video player app generated from an XcodeGen spec.

## Install and update

Download the Apple Silicon DMG from [GitHub Releases](https://github.com/zyuapp/just-play/releases/latest), open it, and drag **Just Play** to **Applications**. Requires macOS 13 or later. The download becomes available after the first release is published.

Release builds are Developer ID signed and notarized by Apple. Just Play checks for updates every six hours using Sparkle. Use **Just Play → Check for Updates…** to check manually; Sparkle guides you through installation and relaunch. Existing builds without Sparkle require a one-time manual installation of the first updater-enabled release.

## Requirements

- macOS 13+
- Xcode 15+
- Homebrew (recommended for installing CLI tools)
- `xcodegen`
- `carthage`

Install tooling:

```bash
brew install xcodegen carthage
```

## Quick Start

1. Fetch dependencies and generate the Xcode project:

   ```bash
   make setup
   ```

2. Build from CLI:

   ```bash
   make build
   ```

3. Build and launch:

   ```bash
   make run
   ```

4. Install the built app into `/Applications` and launch it:

   ```bash
   make install
   ```

   If you prefer user-local install:

   ```bash
   make install APPLICATIONS_DIR=~/Applications
   ```

You can run `make help` to see all available targets.

## Notes

- `Carthage/` is intentionally not committed; every fresh clone should run `make bootstrap` first.
- If Xcode/CoreSimulator version mismatch appears, run:

  ```bash
  xcrun simctl list devices
  ```

## Releases

The **Release** GitHub Actions workflow accepts a `patch`, `minor`, or `major` version bump from `main`:

```bash
gh workflow run Release -R zyuapp/just-play -f bump=patch
```

It increments the app version and build number in `project.yml`, regenerates `Sources/Info.plist`, runs the existing tests, builds for macOS arm64, signs the app and its embedded frameworks, and notarizes the app and DMG. After success, a separate publish job pushes the version commit and tag and publishes the DMG and signed Sparkle `appcast.xml`. The release stays a draft until both assets are uploaded. The first patch release from the current `1.0` version is `1.0.1`.

Configure these GitHub environment secrets in **zyuapp/just-play → Settings → Environments → release** before running the workflow:

| Secret | Value |
| --- | --- |
| `MAC_CERTIFICATE_P12` | Base64-encoded Developer ID certificate and private key export |
| `MAC_CERTIFICATE_PASSWORD` | Password for that export, entered securely |
| `APPLE_API_KEY_P8` | Base64-encoded App Store Connect notarization key |
| `APPLE_API_KEY_ID` | App Store Connect key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `SPARKLE_PRIVATE_KEY` | Sparkle signing key matching `SUPublicEDKey` in `project.yml` |

The Just Play Sparkle key is stored in the maintainer's login Keychain under account `com.justplay`; retain it for future releases. Apple signing credentials are shared with the other apps. Private keys and passwords must stay out of the repository and logs.

The app keeps its existing `com.justplay` bundle identifier and playback-library location. Releases require permission for `GITHUB_TOKEN` to push version commits and tags to `main`; a concurrent change to `main` causes publishing to fail safely instead of overwriting it.

To verify OTA end to end after publishing, install one signed release and check for updates after publishing a newer release. Confirm Sparkle downloads it, requests relaunch, and opens the new version with the playback library intact. Local builds and unit tests do not establish that this installed-app update path works.

## License

- This repository is licensed under MIT (`LICENSE`).
- Third-party dependency notices are listed in `THIRD_PARTY_NOTICES.md`.
