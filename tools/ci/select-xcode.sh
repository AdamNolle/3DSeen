#!/bin/bash
set -euo pipefail

VERSION="${1:?usage: select-xcode.sh <version>}"
CANDIDATES=(
  "/Applications/Xcode_${VERSION}.app"
  "/Applications/Xcode-${VERSION}.app"
)

SELECTED=""
for candidate in "${CANDIDATES[@]}"; do
  if [[ -d "$candidate/Contents/Developer" ]]; then
    SELECTED="$candidate"
    break
  fi
done

if [[ -z "$SELECTED" ]]; then
  SELECTED=$(find /Applications -maxdepth 1 -type d -name "Xcode*${VERSION}*.app" -print | sort | head -1)
fi

if [[ -z "$SELECTED" || ! -d "$SELECTED/Contents/Developer" ]]; then
  echo "Xcode $VERSION is not installed. Available bundles:" >&2
  find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print >&2
  exit 1
fi

sudo xcode-select --switch "$SELECTED/Contents/Developer"
ACTUAL=$(xcodebuild -version | head -1)
if [[ "$ACTUAL" != "Xcode $VERSION" ]]; then
  echo "Expected Xcode $VERSION, selected: $ACTUAL" >&2
  exit 1
fi
xcodebuild -version
