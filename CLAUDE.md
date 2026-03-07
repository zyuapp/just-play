# JustPlay

macOS SwiftUI app generated from an XcodeGen spec.

## Commands

| Command | Description |
| --- | --- |
| `make setup` | Bootstrap Carthage deps and generate the Xcode project. |
| `make build` | Build the app for macOS. |
| `make run` | Build and launch `JustPlay.app`. |
| `make install` | Copy `JustPlay.app` to `/Applications` and open it. Supports `APPLICATIONS_DIR=~/Applications`. |
| `make help` | Show all available Makefile targets. |

## Key rules

- Edit `project.yml` for target, build setting, bundle, or plist changes — never edit `.xcodeproj` directly.
- Use `platform=macOS,arch=arm64` for CLI `xcodebuild` destinations.
- CoreSimulator mismatch errors? Run `xcrun simctl list devices` then retry.
- `xcodebuild` may print `[MT] IDERunDestination: ...is empty.` — this is harmless.
