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

Set repository variable `ENABLE_SIGNED_IOS_RELEASE=true` and configure these encrypted secrets:

- `APPLE_TEAM_ID`
- `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_APP_STORE_PROFILE_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

The profile must target `com.adamnolle.3DSeen-iOS`. The job imports credentials into an ephemeral keychain, creates and validates a signed IPA, uploads it through the App Store Connect API, stores workflow evidence, and removes signing material in an `always()` cleanup step.

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

For a local release with an installed Developer ID certificate, `NOTARYTOOL_KEYCHAIN_PROFILE` can replace the three App Store Connect API variables. Supply the name of a profile already stored by `notarytool`; do not put passwords in repository files. The script records the JSON submission result and requires `Accepted` before stapling.

`tools/release/archive-macos.sh --sign-only` prepares and verifies the signed archive without a submission. Its output explicitly reports `NOTARIZATION_STATUS=not-submitted`; it is not a notarized distribution. `MACOS_DERIVED_DATA` and `MACOS_ARCHIVE_PATH` override the build and archive locations. For an iCloud-backed Desktop checkout, keep both under `~/Library/Developer/Xcode/` to avoid file-provider attributes and launch stalls in generated products.

The Codex Run action uses `script/build_and_run.sh` with ad hoc Debug signing. Use `--verify` for a launch check, `--logs` or `--telemetry` for runtime output, and `--debug` for LLDB. Debug signing does not establish release signing or notarization.

## External gates

Repository scaffolding and unsigned builds do not prove signing, TestFlight acceptance, notarization, Gatekeeper behavior on another Mac, or App Review acceptance. Record those results in `VERIFICATION-STATUS.md` only after credential-backed execution.
