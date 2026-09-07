#!/bin/bash
set -euo pipefail

: "${APPLE_API_KEY_ID:?}"
: "${APPLE_API_ISSUER_ID:?}"
: "${SPARKLE_PRIVATE_KEY:?}"
: "${RUNNER_TEMP:?}"
: "${TAG:?}"

app="build/Build/Products/Release/Just Play.app"
identity="Developer ID Application: Zhuocheng Yu (T3Y739SK63)"
xcodebuild -quiet -project JustPlay.xcodeproj -scheme JustPlay \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# Sign all embedded Mach-O libraries and executables, then their containing
# bundles, from the inside out. VLCKit includes dynamically loaded plugins.
while IFS= read -r -d '' target; do
  if file -b "$target" | grep -q 'Mach-O'; then
    codesign --force --options runtime --timestamp --sign "$identity" "$target"
  fi
done < <(find "$app/Contents/Frameworks" -type f -print0)
while IFS= read -r -d '' target; do
  codesign --force --options runtime --timestamp --sign "$identity" "$target"
done < <(find "$app/Contents/Frameworks" -depth -type d \
  \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0)
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
if codesign -d --entitlements :- "$app" 2>/dev/null | grep -q com.apple.security.get-task-allow; then
  echo 'Release app must not include get-task-allow' >&2
  exit 1
fi

notarize() {
  xcrun notarytool submit "$1" --key "$RUNNER_TEMP/apple.p8" \
    --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" \
    --wait --output-format json > "$RUNNER_TEMP/notary-result.json"
  if ! python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["status"] != "Accepted")' "$RUNNER_TEMP/notary-result.json"; then
    cat "$RUNNER_TEMP/notary-result.json"
    exit 1
  fi
}

submission="$RUNNER_TEMP/JustPlay-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
notarize "$submission"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

mkdir -p dist
artifact="dist/JustPlay-${TAG}-macos-arm64.dmg"
bash scripts/create-dmg.sh "$app" "$artifact"
codesign --force --timestamp --sign "$identity" "$artifact"
notarize "$artifact"
xcrun stapler staple "$artifact"
xcrun stapler validate "$artifact"
spctl --assess --type open --context context:primary-signature --verbose=2 "$artifact"

generate_appcast=$(find build/SourcePackages/artifacts -type f -name generate_appcast -print -quit)
test -n "$generate_appcast"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$generate_appcast" \
  --ed-key-file - --maximum-deltas 0 \
  --download-url-prefix "https://github.com/zyuapp/just-play/releases/download/$TAG/" dist
test -s dist/appcast.xml
