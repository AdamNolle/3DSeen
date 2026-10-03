# Releasing 3DSeen

The canonical release requirements are in [`PRODUCTION-CONTRACT.md`](PRODUCTION-CONTRACT.md). Signing and external upload execution require Apple credentials and are intentionally separate from the credential-free validation path.

## Credential-free dry run

From the repository root:

```bash
RELEASE_VERSION=1.0.0 BUILD_NUMBER=1 tools/release/dry-run.sh
```

This validates plist/YAML/shell syntax, strict SwiftLint, deterministic XcodeGen output, bundle versions, privacy manifests, iPhone/iPad orientation policy, hardened-runtime project configuration, and unsigned iOS/macOS Release builds. Preserved bundles are written beneath `build/release-dry-run/`.

The same path is available through `.github/workflows/release-dry-run.yml` using `workflow_dispatch`, and runs automatically when release configuration changes in a pull request.

## Unsigned tag artifacts

For validation of the current `main` commit without creating a tag or publishing a release, manually run the **Release** workflow with a marketing version and build number. It runs the full iPhone, iPad, and macOS CI suite, then builds and preserves the unsigned Release bundles. The separate **Release Dry Run** workflow validates release metadata and deterministic project generation. Manual validation does not upload to TestFlight or submit for notarization; the credential-backed distribution jobs remain tag-triggered.

A `vMAJOR.MINOR.PATCH` tag runs `.github/workflows/release.yml`. The normal `quality` and `build-artifacts` jobs require no signing secrets and publish unsigned app bundles for verification. `tools/release/validate-version.sh` requires the tag and marketing version to match and uses the GitHub run number as `CURRENT_PROJECT_VERSION`.

## Signed iOS/TestFlight

Set repository variable `ENABLE_SIGNED_IOS_RELEASE=true` and configure these encrypted GitHub Actions secrets:

- `APPLE_TEAM_ID`
- `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_APP_STORE_PROFILE_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

The provisioning profile must target `com.adamnolle.3DSeen-iOS`. CI imports the signing certificate into a short-lived keychain because Apple's signing tools require it, then removes the temporary `.p12` file and keychain during cleanup. The archive script accepts `SIGNING_CERTIFICATE_P12_PATH`, `IOS_PROVISIONING_PROFILE_PATH`, and `APP_STORE_CONNECT_PRIVATE_KEY_PATH` for local runs, so a password manager can supply files only for the duration of a release. App Store Connect `.p8` keys passed through a path are not copied to `$HOME/.private_keys`; base64 CI input is decoded into a restricted temporary directory and removed on exit.

## Developer ID and notarization

Set repository variable `ENABLE_SIGNED_MACOS_RELEASE=true` and configure:

- `APPLE_TEAM_ID`
- `MACOS_DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `MACOS_DEVELOPER_IDENTITY` (full `Developer ID Application: …` identity)
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

The macOS target uses hardened runtime but remains intentionally unsandboxed so its opt-in local COLMAP/Nerfstudio tools can execute. The signed job verifies the code signature/runtime flag, submits a ZIP to `notarytool`, waits for acceptance, staples and validates the ticket, runs Gatekeeper assessment, and uploads the final archive.

For local notarization, authenticate with an App Store Connect **team API key**. Apple does not permit individual API keys to use `notarytool`. Keep the `.p8` file in your password manager and provide it only for the release run with `APP_STORE_CONNECT_PRIVATE_KEY_PATH`, plus `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID`. The script passes that path directly to `notarytool` and does not create a persistent Keychain profile. CI can continue to use the encrypted `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` secret; the script decodes it into a restricted temporary directory and removes that directory on exit.

With Apple Passwords, save the App Store Connect `.p8` text in the notes for a dedicated account. For a local notarization, copy it into a private temporary file without putting it in a command argument or chat:

```bash
set -euo pipefail
umask 077
NOTARY_KEY_DIR="$(mktemp -d)"
chmod 700 "$NOTARY_KEY_DIR"
trap 'rm -rf "$NOTARY_KEY_DIR"' EXIT
cat > "$NOTARY_KEY_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
# Paste the key text from Passwords, then press Control-D.
chmod 600 "$NOTARY_KEY_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
APP_STORE_CONNECT_PRIVATE_KEY_PATH="$NOTARY_KEY_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8" \
  tools/release/archive-macos.sh
```

Set the API key ID and issuer, team ID, Developer ID identity, marketing version, and build number in the release environment as well. The The API key ID, issuer ID, team ID, and Developer ID identity are identifiers, not passwords. Keep the `.p8` private key and certificate import password in Passwords; store the binary `.p12` certificate in encrypted file storage or the CI secret store. Never paste secret values into chat or commit them. Passwords has no CLI connection in this environment, so local retrieval remains a deliberate manual step.

Apple Passwords syncs through iCloud Keychain. This flow avoids a persistent `notarytool` profile in the Mac Keychain, while a short-lived keychain remains necessary for `codesign` to use the Developer ID certificate.

`tools/release/archive-macos.sh --sign-only` prepares and verifies the signed archive without a submission. Its output explicitly reports `NOTARIZATION_STATUS=not-submitted`; it is not a notarized distribution. `MACOS_DERIVED_DATA` and `MACOS_ARCHIVE_PATH` override the build and archive locations. For an iCloud-backed Desktop checkout, keep both under `~/Library/Developer/Xcode/` to avoid file-provider attributes and launch stalls in generated products.

The Codex Run action uses `script/build_and_run.sh` with ad hoc Debug signing. Use `--verify` for a launch check, `--logs` or `--telemetry` for runtime output, and `--debug` for LLDB. Debug signing does not establish release signing or notarization.

## Local Xcode notarization

When an Apple account is already signed in to Xcode, open the Developer ID archive in Organizer, select **Distribute App → Direct Distribution**, wait for **Notarization succeeded**, then export. Verify the exported app independently with `codesign --verify --deep --strict --all-architectures`, `xcrun stapler validate`, and `spctl --assess --type execute --verbose=4`; Gatekeeper must report `Notarized Developer ID`. The October 1 archive completed this path. The scripted release path supplies notarization credentials at runtime and keeps GitHub Actions release secrets configured separately.

## External gates

Repository scaffolding and unsigned builds do not prove signing, TestFlight acceptance, notarization, Gatekeeper behavior on another Mac, or App Review acceptance. Record those results in `VERIFICATION-STATUS.md` only after credential-backed execution.
