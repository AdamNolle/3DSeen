#!/usr/bin/env bash
set -euo pipefail

MODE=${1:-run}
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_NAME=3DSeen-macOS
DERIVED=${MACOS_DERIVED_DATA:-"$HOME/Library/Developer/Xcode/DerivedData/3DSeen-Codex"}
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
xcodebuild build -quiet -project "$ROOT/3DSeen.xcodeproj" -scheme "$APP_NAME" \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
APP="$DERIVED/Build/Products/Debug/$APP_NAME.app"
if [[ "$MODE" == --debug ]]; then
  exec lldb -- "$APP/Contents/MacOS/$APP_NAME"
fi
/usr/bin/open -n "$APP"
case "$MODE" in
  --logs) exec /usr/bin/log stream --info --style compact --predicate "process == '$APP_NAME'" ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate "subsystem BEGINSWITH 'com.adamnolle.3DSeen'" ;;
  --verify) sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
esac
