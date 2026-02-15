# JustPlayNative

JustPlayNative is a macOS SwiftUI video player app generated from an XcodeGen spec.

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

1. Fetch the pinned VLCKit binary dependency:

   ```bash
   carthage bootstrap --use-xcframeworks --platform macOS
   ```

2. Generate the Xcode project from `project.yml`:

   ```bash
   xcodegen generate --use-cache
   ```

3. Build from CLI:

   ```bash
   xcodebuild -project JustPlayNative.xcodeproj -scheme JustPlayNative -destination 'platform=macOS,arch=arm64' build
   ```

4. Build and launch:

   ```bash
   xcodebuild -project JustPlayNative.xcodeproj -scheme JustPlayNative -destination 'platform=macOS,arch=arm64' -derivedDataPath ./.derivedData build && open "./.derivedData/Build/Products/Debug/JustPlayNative.app"
   ```

## Notes

- `Carthage/` is intentionally not committed; every fresh clone should run Carthage bootstrap first.
- If Xcode/CoreSimulator version mismatch appears, run:

  ```bash
  xcrun simctl list devices
  ```

## License

- This repository is licensed under MIT (`LICENSE`).
- Third-party dependency notices are listed in `THIRD_PARTY_NOTICES.md`.
