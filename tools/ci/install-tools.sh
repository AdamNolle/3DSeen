#!/bin/bash
set -euo pipefail

TOOLS_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/3dseen-tools/bin"
DOWNLOAD_DIR="$(mktemp -d)"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
mkdir -p "$TOOLS_DIR"

fetch_and_verify() {
  local url="$1" expected_sha="$2" output="$3"
  curl --fail --location --silent --show-error "$url" --output "$output"
  printf '%s  %s\n' "$expected_sha" "$output" | shasum -a 256 --check --status
}

fetch_and_verify \
  "https://github.com/yonaskolb/XcodeGen/releases/download/2.45.4/xcodegen.zip" \
  "090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef" \
  "$DOWNLOAD_DIR/xcodegen.zip"
unzip -q "$DOWNLOAD_DIR/xcodegen.zip" -d "$DOWNLOAD_DIR/xcodegen"
install -m 0755 "$DOWNLOAD_DIR/xcodegen/xcodegen/bin/xcodegen" "$TOOLS_DIR/xcodegen"

fetch_and_verify \
  "https://github.com/realm/SwiftLint/releases/download/0.65.0/SwiftLintBinary.artifactbundle.zip" \
  "eb333bd76dfb5f46d21fdf3615fe39bb938956ca0b8e94c241c4b2db6e696b90" \
  "$DOWNLOAD_DIR/swiftlint.zip"
unzip -q "$DOWNLOAD_DIR/swiftlint.zip" -d "$DOWNLOAD_DIR/swiftlint"
install -m 0755 \
  "$DOWNLOAD_DIR/swiftlint/SwiftLintBinary.artifactbundle/macos/swiftlint" \
  "$TOOLS_DIR/swiftlint"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$TOOLS_DIR" >> "$GITHUB_PATH"
else
  printf 'Pinned tools installed in %s\n' "$TOOLS_DIR"
fi
