# Just Play

macOS SwiftUI app generated from an XcodeGen spec.

## Commands

| Command | Description |
| --- | --- |
| `make setup` | Bootstrap Carthage deps and generate the Xcode project. |
| `make build` | Build the app for macOS. |
| `make run` | Build and launch `Just Play.app`. |
| `make install` | Copy `Just Play.app` to `/Applications` and open it. Supports `APPLICATIONS_DIR=~/Applications`. |
| `make help` | Show all available Makefile targets. |

## Architecture

Sources are organized in DDD-style layers. Put new code in the layer that matches its role, and keep dependencies pointing inward (Domain depends on nothing app-specific):

- `Sources/Domain/` — pure model and protocol ports; no AppKit, I/O, or SwiftUI.
- `Sources/Application/` — services that orchestrate the playback, library, and subtitle use cases.
- `Sources/Infrastructure/` — concrete adapters implementing Domain ports (file storage, SRT parsing, playback engines).
- `Sources/Presentation/` — SwiftUI views and a thin view model that delegates to Application services.

Follow this layout for new work, but treat it as a guide — don't add layers or indirection a change doesn't need.

## Key rules

- Edit `project.yml` for target, build setting, bundle, or plist changes — never edit `.xcodeproj` directly.
- Use `platform=macOS,arch=arm64` for CLI `xcodebuild` destinations.
- CoreSimulator mismatch errors? Run `xcrun simctl list devices` then retry.
- `xcodebuild` may print `[MT] IDERunDestination: ...is empty.` — this is harmless.
