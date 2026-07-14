# CI/CD Bring-up Log

Last updated: 2026-07-14

## Local status

- [x] XcodeGen 2.45.4 regenerates `3DSeen.xcodeproj`.
- [x] SwiftLint 0.65.0 strict: 0 violations across 81 Swift files.
- [x] iOS Simulator: 110 passed, 0 failed, 1 expected unsigned-Keychain skip on iPhone 17 Pro / iOS 26.5.
- [x] macOS: 37/37 passed, including the locally installed Blender integration.
- [x] iPad adaptive accessibility: 1/1 passed on iPad Pro 13-inch (M5) / iOS 26.5.
- [x] Swift package resolution is committed at `3DSeen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- [x] GitHub Actions CI passed for commit `1c35273`: [run 29135064656](https://github.com/AdamNolle/3DSeen/actions/runs/29135064656).
- [ ] Tag-driven release run confirmed green on the remote repository.

## Workflow hardening completed

- CI pins Xcode 26.3 (required to compile the iOS 26 Liquid Glass APIs), Node 24-compatible GitHub Actions by immutable commit SHA, and checksum-verified XcodeGen 2.45.4 / SwiftLint 0.65.0 release binaries. `tools/ci/select-xcode.sh` replaces the deprecated Node 20 setup action and fails if the exact Xcode bundle is absent.
- The iOS job discovers an available iPhone simulator UDID rather than assuming a model name.
- `xcodebuild` runs once without an uninstalled formatter or a flaky-success fallback rerun; generated project and package-lock drift fails CI.
- Tagged releases invoke the reusable CI workflow first and package artifacts only after lint and both test targets pass.
- Release packaging checks that each `.app` exists before creating or publishing archives.
- The Metal Toolchain installation remains a guarded no-op on Xcode versions that bundle it.

## Remaining remote-only checks

1. Push a release-candidate tag and verify the unsigned iOS/macOS artifacts and generated GitHub Release.
2. If the `macos-15` image removes Xcode 26.3, deliberately advance the pinned version and rerun the full matrix; do not return to `latest-stable`.
3. Blender is not provisioned in hosted CI, so the real Blender test skips there. Command construction, failure preservation, and format validation still run; the installed-runtime integration is local evidence documented in `docs/VERIFICATION-STATUS.md`.
