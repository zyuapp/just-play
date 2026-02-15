# Third-Party Notices

This repository currently depends on the third-party component below.

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

## Tooling (Not Redistributed as Part of App Runtime)

- XcodeGen (project generation)
- Carthage (dependency bootstrap)

These tools are used to build the project and are not linked into the application runtime.
