# Third-Party Notices

This repository depends on the third-party components below.

## Runtime Dependency

### VLCKit

- Upstream: VideoLAN
- Version: 3.7.2 (pinned in `Cartfile.resolved`)
- Source: `https://code.videolan.org/videolan/VLCKit/raw/master/Packaging/VLCKit.json`
- Integration: `Carthage/Build/VLCKit.xcframework` (referenced in `project.yml`)
- License: GNU Lesser General Public License v2.1 or later (LGPL-2.1-or-later)

The VLCKit headers in the downloaded framework include LGPL-2.1-or-later notices.

License text:
- https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt

If you redistribute binaries that include or link against VLCKit, you are responsible for meeting applicable LGPL requirements.

### Sparkle

- Upstream: https://github.com/sparkle-project/Sparkle
- Version: 2.9.2 (pinned in `project.yml`)
- Purpose: Signed in-app software updates
- License: MIT, with additional notices for bundled components
- Complete license notices are included in `Sources/Resources/Sparkle-LICENSE.txt` and bundled with the app.

## Tooling (Not Redistributed as Part of App Runtime)

- XcodeGen (project generation)
- Carthage (dependency bootstrap)

These tools are used to build the project and are not linked into the application runtime.
