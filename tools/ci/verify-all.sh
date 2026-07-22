#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
OUTPUT_ROOT=${FINAL_OUTPUT_ROOT:-"$ROOT/build/final-verification"}
IOS_DEVICE_ID=${IOS_DEVICE_ID:-}
IPAD_DEVICE_ID=${IPAD_DEVICE_ID:-}
MINIMUM_XCODE_VERSION=${MINIMUM_XCODE_VERSION:-26.3}
mkdir -p "$OUTPUT_ROOT/logs"

for command in xcodebuild xcodegen swiftlint ruby python3 plutil; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 1; }
done

ACTUAL_XCODE_VERSION=$(xcodebuild -version | awk 'NR == 1 { print $2 }')
python3 - "$MINIMUM_XCODE_VERSION" "$ACTUAL_XCODE_VERSION" <<'PY'
import sys
def version(value): return tuple(int(part) for part in value.split('.'))
if version(sys.argv[2]) < version(sys.argv[1]):
    raise SystemExit(f'Xcode {sys.argv[1]} or newer is required; found {sys.argv[2]}')
PY

python3 - <<'PY'
from pathlib import Path
import re
allowed = {
    ('actions/checkout', 'de0fac2e4500dabe0009e67214ff5f5447ce83dd'),
    ('actions/upload-artifact', 'b7c566a772e6b6bfb58ed0dc250532a479d7789f'),
    ('softprops/action-gh-release', 'b4309332981a82ec1c5618f44dd2e27cc8bfbfda'),
}
for path in Path('.github/workflows').glob('*.yml'):
    for line in path.read_text().splitlines():
        match = re.search(r'uses:\s+([^\s]+)@([^\s#]+)', line)
        if not match or match.group(1).startswith('./'):
            continue
        reference = (match.group(1), match.group(2))
        if reference not in allowed:
            raise SystemExit(f'{path}: external action is not on the audited Node 24 SHA allowlist: {line.strip()}')
PY

python3 tools/assets/validate-app-icons.py | tee "$OUTPUT_ROOT/logs/app-icon-validation.log"

PROJECT_HASH_BEFORE=$(shasum -a 256 3DSeen.xcodeproj/project.pbxproj | awk '{ print $1 }')
xcodegen generate | tee "$OUTPUT_ROOT/logs/xcodegen-drift.log"
PROJECT_HASH_AFTER=$(shasum -a 256 3DSeen.xcodeproj/project.pbxproj | awk '{ print $1 }')
[[ "$PROJECT_HASH_BEFORE" == "$PROJECT_HASH_AFTER" ]] || {
  echo "XcodeGen drift detected: regenerate and commit 3DSeen.xcodeproj" >&2
  exit 1
}

RELEASE_OUTPUT_ROOT="$OUTPUT_ROOT/release" \
  RELEASE_VERSION=9.8.7 BUILD_NUMBER=123 \
  tools/release/dry-run.sh | tee "$OUTPUT_ROOT/logs/release-dry-run.log"

rm -rf "$OUTPUT_ROOT/tests-ios" "$OUTPUT_ROOT/tests-macos" "$OUTPUT_ROOT/tests-ipad"

if [[ -z "$IOS_DEVICE_ID" ]]; then
  IOS_DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
items = [d for runtime in devices.values() for d in runtime
         if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not items: raise SystemExit("No available iPhone Simulator")
print(items[0]["udid"])
')
fi
if [[ -z "$IPAD_DEVICE_ID" ]]; then
  IPAD_DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
items = [d for runtime in devices.values() for d in runtime
         if d.get("isAvailable") and d["name"].startswith("iPad")]
if not items: raise SystemExit("No available iPad Simulator")
print(items[0]["udid"])
')
fi

xcodebuild test -quiet \
  -project 3DSeen.xcodeproj -scheme 3DSeen-iOS \
  -destination "platform=iOS Simulator,id=$IOS_DEVICE_ID" \
  -derivedDataPath "$OUTPUT_ROOT/tests-ios" CODE_SIGNING_ALLOWED=NO \
  | tee "$OUTPUT_ROOT/logs/ios-tests.log"
IOS_RESULT=$(find "$OUTPUT_ROOT/tests-ios/Logs/Test" -name '*.xcresult' -type d -print | sort | tail -1)
xcrun xcresulttool get test-results summary --path "$IOS_RESULT" --format json \
  > "$OUTPUT_ROOT/logs/ios-summary.json"

xcodebuild test -quiet \
  -project 3DSeen.xcodeproj -scheme 3DSeen-macOS \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$OUTPUT_ROOT/tests-macos" CODE_SIGNING_ALLOWED=NO \
  | tee "$OUTPUT_ROOT/logs/macos-tests.log"
MAC_RESULT=$(find "$OUTPUT_ROOT/tests-macos/Logs/Test" -name '*.xcresult' -type d -print | sort | tail -1)
xcrun xcresulttool get test-results summary --path "$MAC_RESULT" --format json \
  > "$OUTPUT_ROOT/logs/macos-summary.json"

xcodebuild test -quiet \
  -project 3DSeen.xcodeproj -scheme 3DSeen-iOS \
  -destination "platform=iOS Simulator,id=$IPAD_DEVICE_ID" \
  -derivedDataPath "$OUTPUT_ROOT/tests-ipad" CODE_SIGNING_ALLOWED=NO \
  -only-testing:3DSeen-iOSUITests/WizardFlowUITests/testAccessibilityDynamicTypeKeepsSettingsAndViewerActionsReachable \
  -only-testing:3DSeen-iOSUITests/WizardFlowUITests/testRegularWizardSurfacesExposeGuidedChoices \
  | tee "$OUTPUT_ROOT/logs/ipad-accessibility.log"
IPAD_RESULT=$(find "$OUTPUT_ROOT/tests-ipad/Logs/Test" -name '*.xcresult' -type d -print | sort | tail -1)
xcrun xcresulttool get test-results summary --path "$IPAD_RESULT" --format json \
  > "$OUTPUT_ROOT/logs/ipad-summary.json"

IOS_APP=$(find "$OUTPUT_ROOT/release/ios/Build/Products" -name '3DSeen-iOS.app' -print -quit)
MAC_APP=$(find "$OUTPUT_ROOT/release/mac/Build/Products" -name '3DSeen-macOS.app' -print -quit)
! strings "$IOS_APP/3DSeen-iOS" | grep -E '3dseen-demo-splat|celestial-bust'
! strings "$MAC_APP/Contents/MacOS/3DSeen-macOS" | grep -E '3dseen-demo-splat|celestial-bust'

git diff --check
python3 - "$OUTPUT_ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1]) / 'logs'
lines = []
for label, name in [('iOS', 'ios-summary.json'), ('macOS', 'macos-summary.json'), ('iPad UI', 'ipad-summary.json')]:
    data = json.loads((root / name).read_text())
    lines.append(f"{label}: {data['passedTests']} passed, {data['failedTests']} failed, {data['skippedTests']} skipped")
summary = '\n'.join(lines) + '\nRelease dry run: passed\nXcodeGen drift: passed\nApp icon catalogs: validated opaque RGB assets\nAction pins: audited Node 24 SHA allowlist passed\n'
(root / 'summary.txt').write_text(summary)
print(summary, end='')
PY

echo "Final verification artifacts: $OUTPUT_ROOT"
