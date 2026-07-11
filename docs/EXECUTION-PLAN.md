# 3DSeen Studio — Execution Plan (design → faithful native app)

Goal: implement the Claude Design "3DSeen Studio" faithfully across **iPhone, iPad, Mac**, feature-complete, performant, bug-free. Source of truth: `docs/design-spec/*.md` (+ `docs/design-ref/*.jsx` raw). Current state: `docs/current-impl-map.md`. Per-target gaps: `docs/audit/*.md`.

## Device → platform mapping (decided)
- **iPhone** = iOS compact. The 10-screen wizard flow (`library → mode → briefing → viewfinder → quality → review → compute → viewer → export → settings`).
- **iPad** = iOS regular. **Same wizard flow**, but each screen gets a **bespoke two-column / sidebar layout** per its spec's "Pad" variant — NOT width-reflow. Implemented per-screen via `horizontalSizeClass` inside each screen file. (iPad is NOT a persistent-sidebar app; it's the wizard at desk scale.)
- **Mac** = the macOS target: a persistent **sidebar + detail + inspector** app with 5 panes (`library, viewer, compute, export, settings`). Lives in `Sources/macOS/ContentView.swift`.

## Architecture decisions
- Tokens/components stay in `Sources/Shared/DesignSystem` (`St`-prefixed). All screens consume them; never hardcode hex.
- Per-screen iPhone+iPad layout co-locates in each `*Screen.swift` (clean file partition → parallel-safe).
- 3D model areas (Viewer hero, coverage) use real SceneKit/RealityKit/MetalSplatter where the design shows a model; decorative thumbnails/charts may stay Canvas.
- Wiring: a single `@AppStorage`-backed settings store; dark-mode toggle reachable from iOS Settings; Library search/filter functional; Viewer AR → QuickLook of exported USDZ; Export writes real files (already wired) and surfaces share.

## Phases (each phase = one workflow; verify between)
**P0 — Baseline (DONE):** project regenerates, both targets build/test, and strict lint is clean. Simulator destinations are selected by available UDID rather than a hard-coded runtime.

**P1 — Foundation reconciliation (shared files, careful/sequential):**
- Theme tokens exact vs `00-foundation §1` (light+dark, every key).
- Primitives complete & matching §3 (Glass/Card/Button/Label/Stat/Segmented/Toggle/Chip/Meter/Ring/Rule); wire or remove dead helpers (Spark/Histogram/FrameStrip/StSegmented) per where the design uses them.
- Shared chrome + infra: size-class plumbing, settings store, iOS dark-mode reachability, haptics/a11y helpers.
Locks the API before screen fan-out.

**P2 — Per-screen implementation (fan-out, disjoint files):** one agent per screen owns `*Screen.swift`; reconciles iPhone fidelity (copy/layout/tokens/interactions) + builds the bespoke iPad layout + wires functional behavior. 10 agents, parallel.

**P3 — macOS app (focused):** realize all 5 Mac panes (add Settings pane; sidebar+detail+inspector fidelity) in `ContentView.swift`.

**P4 — Wiring & realness:** make mocks functional (search, settings persistence, dark toggle, AR, handoff honesty, surface real capture where the wizard shutter fires).

**P5 — Verify loop (repeat until perfect):** `xcodegen generate` → build iOS (booted 26.4 sim) + macOS → `xcodebuild test` both → `swiftlint --strict` → boot sim, screenshot each screen × device, compare to `docs/design-ref` + design screenshots → fix → repeat. Performance pass (no jank, lazy loading, no over-redraw).

## Build/test invocation (environment-pinned)
- Regenerate after file add/remove: `xcodegen generate`.
- iOS sim: choose an installed device ID with `xcrun simctl list devices available` (latest local verification used iPhone 17 at iOS 26.5). Avoid hard-coded model/runtime names.
- Build iOS: `xcodebuild build -scheme 3DSeen-iOS -destination "platform=iOS Simulator,id=<DEV>" -derivedDataPath .dd CODE_SIGNING_ALLOWED=NO`
- Build mac: `xcodebuild build -scheme 3DSeen-macOS -destination 'platform=macOS' -derivedDataPath .dd CODE_SIGNING_ALLOWED=NO`
- Lint: `swiftlint lint --strict`
- Tests: `xcodebuild test -scheme 3DSeen-iOS -destination "platform=iOS Simulator,id=<DEV>" ...` and `-scheme 3DSeen-macOS -destination 'platform=macOS'`.

## Parallel-safety rule
Agents may edit DISJOINT files concurrently (each screen file is independent). Shared files (Theme/Primitives/Router/Chrome/macOS ContentView) are edited only in the dedicated foundation/mac phases, never during screen fan-out.
