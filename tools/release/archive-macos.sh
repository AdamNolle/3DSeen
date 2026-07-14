#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_TEAM_ID:?Missing Apple team ID}"
: "${MACOS_DEVELOPER_IDENTITY:?Missing Developer ID Application identity}"
: "${MARKETING_VERSION:?Missing marketing version}"
: "${CURRENT_PROJECT_VERSION:?Missing build number}"
: "${APP_STORE_CONNECT_KEY_ID:?Missing App Store Connect key ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Missing App Store Connect issuer ID}"
: "${APP_STORE_CONNECT_PRIVATE_KEY_BASE64:?Missing App Store Connect private key}"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUTPUT_ROOT=${RELEASE_OUTPUT_ROOT:-"$ROOT/dist/signed-macos"}
ARCHIVE_PATH="$OUTPUT_ROOT/3DSeen-macOS.xcarchive"
NOTARY_KEY="${RUNNER_TEMP:-/tmp}/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
SUBMISSION_ZIP="$OUTPUT_ROOT/3DSeen-macOS-notary-submission.zip"
FINAL_ZIP="$OUTPUT_ROOT/3DSeen-macOS-${MARKETING_VERSION}.zip"
mkdir -p "$OUTPUT_ROOT"

xcodebuild archive \
  -project "$ROOT/3DSeen.xcodeproj" \
  -scheme 3DSeen-macOS \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$MACOS_DEVELOPER_IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS='--timestamp'

APP="$ARCHIVE_PATH/Products/Applications/3DSeen-macOS.app"
test -d "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if ! codesign -d --verbose=4 "$APP" 2>&1 | grep -q 'flags=.*runtime'; then
  echo 'Archived app is missing the hardened runtime flag.' >&2
  exit 1
fi

rm -f "$SUBMISSION_ZIP" "$FINAL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION_ZIP"
printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY_BASE64" | base64 --decode > "$NOTARY_KEY"
chmod 600 "$NOTARY_KEY"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --key "$NOTARY_KEY" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ZIP"
rm -f "$NOTARY_KEY" "$SUBMISSION_ZIP"

printf 'SIGNED_MAC_ZIP=%s\n' "$FINAL_ZIP"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'zip=%s\n' "$FINAL_ZIP" >> "$GITHUB_OUTPUT"
fi
