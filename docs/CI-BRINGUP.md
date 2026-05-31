# CI/CD Bring-up Log

What needs to happen to get GitHub Actions green, and the known risks.

## Plan
1. **Commit** the full implementation to `main` (greenfield repo; respects `.gitignore`).
2. **Create** a private GitHub repo `AdamNolle/3DSeen` and push `main` → triggers `ci.yml`.
3. **Drive `ci.yml` green** — 3 jobs: SwiftLint (strict), Build & Test iOS, Build & Test macOS.
4. **Drive `release.yml` green** — push tag `v0.1.0` → builds unsigned artifacts + GitHub Release.

## Known risks on the runner (GitHub `macos-15`)
- **Xcode version drift.** Built locally on Xcode 26.5 / iOS 26 SDK. The runner's `latest-stable` may be Xcode 16/17 (iOS 18/19 SDK). The SDK-drift fixes (no `isAutoMaskingEnabled`, no `checkpointDirectory`, guarded `Host.current()`) keep it iOS-17-compatible, but new failures may surface and need fixing.
- **Metal Toolchain.** MetalSplatter compiles `.metal` shaders. On Xcode 16 the compiler is bundled (the `-downloadComponent MetalToolchain` step is a `|| true` no-op); on Xcode 26 the component download is required (handled).
- **Simulator name.** Tests target `platform=iOS Simulator,name=iPhone 16`. If the runner image lacks that exact device, switch to an available one.
- **Formatter availability.** Avoid piping to `xcpretty`/`xcbeautify` unless installed; run `xcodebuild` directly for reliability.
- **SPM resolution.** `Package.resolved` is gitignored; the runner resolves fresh against the `from:` constraints.

## Status
- [x] Local: SwiftLint strict clean; 28 iOS + 4 macOS tests pass; both targets build.
- [ ] CI green
- [ ] CD green
