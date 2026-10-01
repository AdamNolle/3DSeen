#!/usr/bin/env bash
set -euo pipefail
MODE=${1:-notarize}
[[ "$MODE" == notarize || "$MODE" == --sign-only ]] || { echo "usage: $0 [--sign-only]" >&2; exit 2; }

: "${APPLE_TEAM_ID:?Missing Apple team ID}"
: "${MACOS_DEVELOPER_IDENTITY:?Missing Developer ID Application identity}"
: "${MARKETING_VERSION:?Missing marketing version}"
: "${CURRENT_PROJECT_VERSION:?Missing build number}"
if [[ "$MODE" == notarize && -z "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
  : "${APP_STORE_CONNECT_KEY_ID:?Missing App Store Connect key ID or NOTARYTOOL_KEYCHAIN_PROFILE}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?Missing App Store Connect issuer ID}"
  : "${APP_STORE_CONNECT_PRIVATE_KEY_BASE64:?Missing App Store Connect private key}"
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUTPUT_ROOT=${RELEASE_OUTPUT_ROOT:-"$ROOT/dist/signed-macos"}
ARCHIVE_PATH=${MACOS_ARCHIVE_PATH:-"$OUTPUT_ROOT/3DSeen-macOS.xcarchive"}
DERIVED_DATA_PATH=${MACOS_DERIVED_DATA:-"$HOME/Library/Developer/Xcode/DerivedData/3DSeen-Release"}
KEY_DIRECTORY=""
SUBMISSION_ZIP="$OUTPUT_ROOT/3DSeen-macOS-notary-submission.zip"
FINAL_ZIP="$OUTPUT_ROOT/3DSeen-macOS-${MARKETING_VERSION}.zip"
mkdir -p "$OUTPUT_ROOT"
cleanup() {
  if [[ -n "$KEY_DIRECTORY" ]]; then rm -rf "$KEY_DIRECTORY"; fi
}
trap cleanup EXIT

xcodebuild archive \
  -project "$ROOT/3DSeen.xcodeproj" \
  -scheme 3DSeen-macOS \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
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
codesign -d --verbose=4 "$APP" > "$OUTPUT_ROOT/signature.txt" 2>&1
if ! grep -q 'flags=.*runtime' "$OUTPUT_ROOT/signature.txt"; then
  echo 'Archived app is missing the hardened runtime flag.' >&2
  exit 1
fi

if [[ "$MODE" == --sign-only ]]; then
  printf 'SIGNED_MAC_APP=%s\nNOTARIZATION_STATUS=not-submitted\n' "$APP"
  exit 0
fi

rm -f "$SUBMISSION_ZIP" "$FINAL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION_ZIP"
if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
  NOTARY_ARGUMENTS=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
else
  KEY_DIRECTORY=$(mktemp -d "${RUNNER_TEMP:-/tmp}/3dseen-notary.XXXXXX")
  NOTARY_KEY="$KEY_DIRECTORY/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  (umask 077; printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY_BASE64" | base64 --decode > "$NOTARY_KEY")
  NOTARY_ARGUMENTS=(--key "$NOTARY_KEY" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID")
fi
xcrun notarytool submit "$SUBMISSION_ZIP" "${NOTARY_ARGUMENTS[@]}" \
  --wait --output-format json > "$OUTPUT_ROOT/notarization.json"
if ! python3 - "$OUTPUT_ROOT/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print(f"Notarization {result.get('id', 'unknown')}: {result.get('status', 'unknown')}")
sys.exit(0 if result.get('status') == 'Accepted' else 1)
PY
then
  echo "Notarization was not accepted; see $OUTPUT_ROOT/notarization.json" >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ZIP"
rm -f "$SUBMISSION_ZIP"

printf 'SIGNED_MAC_ZIP=%s\n' "$FINAL_ZIP"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'zip=%s\n' "$FINAL_ZIP" >> "$GITHUB_OUTPUT"
fi
