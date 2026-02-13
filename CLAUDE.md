# JustPlayNative

macOS SwiftUI app generated from an XcodeGen spec.

## Commands

| Command | Description |
| --- | --- |
| `xcodegen dump --type summary` | Validate the resolved XcodeGen spec and target summary. |
| `xcodegen generate --use-cache` | Regenerate `JustPlayNative.xcodeproj` and plist outputs from `project.yml`. |
| `xcodebuild -project JustPlayNative.xcodeproj -scheme JustPlayNative -destination 'platform=macOS,arch=arm64' build` | Build the app from CLI for Apple Silicon macOS. |
| `xcodebuild -project JustPlayNative.xcodeproj -scheme JustPlayNative -destination 'platform=macOS,arch=arm64' -derivedDataPath ./.derivedData build && open "./.derivedData/Build/Products/Debug/JustPlayNative.app"` | Build and launch from CLI. |
| `xcrun simctl list devices` | Refresh CoreSimulator service state if Xcode/CoreSimulator mismatch errors appear. |

## Architecture

```text
project.yml                # Source-of-truth XcodeGen spec
JustPlayNative.xcodeproj/  # Generated project; regenerate instead of manual edits
Sources/
  JustPlayNativeApp.swift  # @main app entry
  ContentView.swift        # Main window UI
  Info.plist               # Generated/synced from project.yml info properties
```

## Workflow

1. Edit `project.yml` for target, build setting, bundle, or plist changes.
2. Run `xcodegen generate --use-cache`.
3. Build with `xcodebuild` using `-destination 'platform=macOS,arch=arm64'`.
4. Launch the built app from `.derivedData/Build/Products/Debug/JustPlayNative.app` when running via CLI.

## Gotchas

- `xcodebuild` may print `[MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.` while still producing a successful build.
- On Apple Silicon, `xcodebuild -destination 'platform=macOS'` can warn about multiple matching destinations; use `platform=macOS,arch=arm64` for deterministic CLI builds.
- If you see CoreSimulator version mismatch errors during build startup, run `xcrun simctl list devices` once to let CoreSimulator refresh stale service state, then retry.
