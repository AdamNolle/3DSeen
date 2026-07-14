#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_TEAM_ID:?Missing Apple team ID}"
: "${IOS_PROVISIONING_PROFILE_BASE64:?Missing iOS provisioning profile}"
: "${MARKETING_VERSION:?Missing marketing version}"
: "${CURRENT_PROJECT_VERSION:?Missing build number}"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUTPUT_ROOT=${RELEASE_OUTPUT_ROOT:-"$ROOT/dist/signed-ios"}
ARCHIVE_PATH="$OUTPUT_ROOT/3DSeen-iOS.xcarchive"
EXPORT_PATH="$OUTPUT_ROOT/export"
PROFILE_PATH="${RUNNER_TEMP:-/tmp}/3dseen.mobileprovision"
PROFILE_PLIST="${RUNNER_TEMP:-/tmp}/3dseen-profile.plist"
EXPORT_OPTIONS="${RUNNER_TEMP:-/tmp}/3dseen-export-options.plist"
mkdir -p "$OUTPUT_ROOT" "$HOME/Library/MobileDevice/Provisioning Profiles"

printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"
security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PROFILE_PLIST")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$PROFILE_PLIST")
PROFILE_TEAM=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$PROFILE_PLIST")
PROFILE_BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROFILE_PLIST")
BUNDLE_ID=${PROFILE_BUNDLE#*.}
[[ "$PROFILE_TEAM" == "$APPLE_TEAM_ID" ]] || { echo "Provisioning profile team mismatch." >&2; exit 1; }
[[ "$BUNDLE_ID" == "com.adamnolle.3DSeen-iOS" ]] || { echo "Unexpected profile bundle ID '$BUNDLE_ID'." >&2; exit 1; }
cp "$PROFILE_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>$APPLE_TEAM_ID</string>
<key>provisioningProfiles</key><dict>
<key>$BUNDLE_ID</key><string>$PROFILE_NAME</string>
</dict>
<key>stripSwiftSymbols</key><true/>
<key>uploadSymbols</key><true/>
</dict></plist>
PLIST

xcodebuild archive \
  -project "$ROOT/3DSeen.xcodeproj" \
  -scheme 3DSeen-iOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME"

rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"
IPA=$(find "$EXPORT_PATH" -name '*.ipa' -print -quit)
test -n "$IPA" && test -f "$IPA"
unzip -t "$IPA" >/dev/null
printf 'SIGNED_IOS_IPA=%s\n' "$IPA"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'ipa=%s\n' "$IPA" >> "$GITHUB_OUTPUT"
fi

if [[ "${UPLOAD_TO_APP_STORE:-false}" == "true" ]]; then
  : "${APP_STORE_CONNECT_KEY_ID:?Missing App Store Connect key ID}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?Missing App Store Connect issuer ID}"
  : "${APP_STORE_CONNECT_PRIVATE_KEY_BASE64:?Missing App Store Connect private key}"
  mkdir -p "$HOME/.private_keys"
  KEY_PATH="$HOME/.private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY_BASE64" | base64 --decode > "$KEY_PATH"
  chmod 600 "$KEY_PATH"
  xcrun altool --upload-app --type ios --file "$IPA" \
    --apiKey "$APP_STORE_CONNECT_KEY_ID" \
    --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
fi
