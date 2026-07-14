#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SIGNING_KEYCHAIN_PATH:-}" ]]; then
  security delete-keychain "$SIGNING_KEYCHAIN_PATH" 2>/dev/null || true
fi
rm -f "${RUNNER_TEMP:-/tmp}/3dseen-signing.p12"
rm -rf "${HOME}/.private_keys"
