# CI/CD Bring-up Log

Last updated: 2026-07-10

## Local status

- [x] XcodeGen 2.45.4 regenerates `3DSeen.xcodeproj`.
- [x] SwiftLint 0.65.0 strict: 0 violations across 66 Swift files.
- [x] iOS Simulator: 70 tests pass on iPhone 17 / iOS 26.5.
- [x] macOS: 33 tests pass, including the locally installed Blender integration.
- [x] Swift package resolution is committed at `3DSeen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- [x] GitHub Actions CI passed for commit `1c35273`: [run 29135064656](https://github.com/AdamNolle/3DSeen/actions/runs/29135064656).
- [ ] Tag-driven release run confirmed green on the remote repository.

## Workflow hardening completed

- CI pins Xcode 26.3 (required to compile the iOS 26 Liquid Glass APIs), GitHub Actions by commit SHA, and checksum-verified XcodeGen 2.45.4 / SwiftLint 0.65.0 release binaries.
- The iOS job discovers an available iPhone simulator UDID rather than assuming a model name.
- `xcodebuild` runs once without an uninstalled formatter or a flaky-success fallback rerun; generated project and package-lock drift fails CI.
- Tagged releases invoke the reusable CI workflow first and package artifacts only after lint and both test targets pass.
- Release packaging checks that each `.app` exists before creating or publishing archives.
- The Metal Toolchain installation remains a guarded no-op on Xcode versions that bundle it.

## Remaining remote-only checks

1. Push a release-candidate tag and verify the unsigned iOS/macOS artifacts and generated GitHub Release.
2. If the `macos-15` image removes Xcode 26.3, deliberately advance the pinned version and rerun the full matrix; do not return to `latest-stable`.
3. Blender is not provisioned in hosted CI, so the real Blender test skips there. Command construction, failure preservation, and format validation still run; the installed-runtime integration is local evidence documented in `docs/VERIFICATION-STATUS.md`.
