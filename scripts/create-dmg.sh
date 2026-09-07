#!/bin/bash
set -euo pipefail

app_path=${1:?usage: create-dmg.sh /path/to/App.app /path/to/output.dmg}
dmg_path=${2:?usage: create-dmg.sh /path/to/App.app /path/to/output.dmg}
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_path" "$staging_dir/Just Play.app"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "$(dirname "$dmg_path")"
hdiutil create -quiet -volname "Just Play" -srcfolder "$staging_dir" -format UDZO "$dmg_path"
