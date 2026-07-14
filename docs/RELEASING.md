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

## External gates

Repository scaffolding and unsigned builds do not prove signing, TestFlight acceptance, notarization, Gatekeeper behavior on another Mac, or App Review acceptance. Record those results in `VERIFICATION-STATUS.md` only after credential-backed execution.
