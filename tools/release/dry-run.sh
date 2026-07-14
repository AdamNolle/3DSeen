#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
RELEASE_VERSION=${RELEASE_VERSION:-1.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
OUTPUT_ROOT=${RELEASE_OUTPUT_ROOT:-"$ROOT/build/release-dry-run"}
IOS_DERIVED="$OUTPUT_ROOT/ios"
MAC_DERIVED="$OUTPUT_ROOT/mac"
SNAPSHOT=$(mktemp -d)
trap 'rm -rf "$SNAPSHOT"' EXIT

RELEASE_VERSION="$RELEASE_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
  tools/release/validate-version.sh
plutil -lint Sources/Shared/PrivacyInfo.xcprivacy Sources/iOS/Info.plist Sources/macOS/Info.plist
bash -n tools/release/*.sh
ruby -e 'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }' .github/workflows/*.yml project.yml
swiftlint lint --strict

cp 3DSeen.xcodeproj/project.pbxproj "$SNAPSHOT/project.pbxproj"
cp 3DSeen.xcodeproj/xcshareddata/xcschemes/3DSeen-iOS.xcscheme "$SNAPSHOT/ios.xcscheme"
cp Sources/iOS/Info.plist "$SNAPSHOT/ios-info.plist"
cp Sources/macOS/Info.plist "$SNAPSHOT/mac-info.plist"
xcodegen generate
cmp "$SNAPSHOT/project.pbxproj" 3DSeen.xcodeproj/project.pbxproj
cmp "$SNAPSHOT/ios.xcscheme" 3DSeen.xcodeproj/xcshareddata/xcschemes/3DSeen-iOS.xcscheme
cmp "$SNAPSHOT/ios-info.plist" Sources/iOS/Info.plist
cmp "$SNAPSHOT/mac-info.plist" Sources/macOS/Info.plist

rm -rf "$OUTPUT_ROOT"
xcodebuild build -quiet \
  -project 3DSeen.xcodeproj -scheme 3DSeen-iOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$IOS_DERIVED" \
  MARKETING_VERSION="$RELEASE_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -quiet \
  -project 3DSeen.xcodeproj -scheme 3DSeen-macOS -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$MAC_DERIVED" \
  MARKETING_VERSION="$RELEASE_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

IOS_APP=$(find "$IOS_DERIVED/Build/Products" -name '3DSeen-iOS.app' -print -quit)
MAC_APP=$(find "$MAC_DERIVED/Build/Products" -name '3DSeen-macOS.app' -print -quit)
test -d "$IOS_APP" && test -d "$MAC_APP"
test "$(plutil -extract CFBundleShortVersionString raw "$IOS_APP/Info.plist")" = "$RELEASE_VERSION"
test "$(plutil -extract CFBundleVersion raw "$IOS_APP/Info.plist")" = "$BUILD_NUMBER"
test "$(plutil -extract CFBundleShortVersionString raw "$MAC_APP/Contents/Info.plist")" = "$RELEASE_VERSION"
test "$(plutil -extract CFBundleVersion raw "$MAC_APP/Contents/Info.plist")" = "$BUILD_NUMBER"
test -f "$IOS_APP/PrivacyInfo.xcprivacy"
test -f "$MAC_APP/Contents/Resources/PrivacyInfo.xcprivacy"
test "$(plutil -extract UIRequiresFullScreen raw "$IOS_APP/Info.plist")" = false
test "$(plutil -extract 'UISupportedInterfaceOrientations~ipad' json -o - "$IOS_APP/Info.plist" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" = 4
grep -q 'ENABLE_HARDENED_RUNTIME: YES' project.yml

git diff --check
printf 'Release dry run passed for %s (%s).\niOS: %s\nmacOS: %s\n' \
  "$RELEASE_VERSION" "$BUILD_NUMBER" "$IOS_APP" "$MAC_APP"
