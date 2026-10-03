#!/usr/bin/env bash
set -euo pipefail

: "${SIGNING_CERTIFICATE_PASSWORD:?Missing certificate password}"
KEYCHAIN_PATH=${SIGNING_KEYCHAIN_PATH:-"${RUNNER_TEMP:-/tmp}/3dseen-signing.keychain-db"}
KEYCHAIN_PASSWORD=${SIGNING_KEYCHAIN_PASSWORD:-"$(uuidgen)$(uuidgen)"}
CERTIFICATE_PATH="${RUNNER_TEMP:-/tmp}/3dseen-signing.p12"
trap 'rm -f "$CERTIFICATE_PATH"' EXIT

if [[ -n "${SIGNING_CERTIFICATE_P12_PATH:-}" ]]; then
  [[ -f "$SIGNING_CERTIFICATE_P12_PATH" && -r "$SIGNING_CERTIFICATE_P12_PATH" ]] || {
    echo 'SIGNING_CERTIFICATE_P12_PATH is not a readable file.' >&2
    exit 1
  }
  cp "$SIGNING_CERTIFICATE_P12_PATH" "$CERTIFICATE_PATH"
else
  : "${SIGNING_CERTIFICATE_P12_BASE64:?Set a certificate file path or base64 value}"
  printf '%s' "$SIGNING_CERTIFICATE_P12_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
fi
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" -P "$SIGNING_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
rm -f "$CERTIFICATE_PATH"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'SIGNING_KEYCHAIN_PATH=%s\nSIGNING_KEYCHAIN_PASSWORD=%s\n' \
    "$KEYCHAIN_PATH" "$KEYCHAIN_PASSWORD" >> "$GITHUB_ENV"
fi
printf 'Imported signing certificate into ephemeral keychain %s\n' "$KEYCHAIN_PATH"
