# Audit — Compute screen (`compute`)

Spec sources: `docs/design-spec/compute.md`, `docs/design-ref/screens/compute.jsx` (ground truth), `docs/design-spec/00-foundation.md`.
Swift under audit: `Sources/iOS/Studio/Screens/ComputeScreen.swift` (iPhone), `Sources/macOS/ContentView.swift` → `MacComputePane` (Mac). No iPad layout exists.

The prototype defines **three** bespoke variants for this screen: `PhoneCompute`, `PadCompute`, and `MacCompute`.
- **iPhone** is ported and is high fidelity.
- **iPad** has **no bespoke layout at all** — the router renders the phone `ComputeScreen` centered/width-capped (`readableContentWidth(720)`). The entire hub-and-spoke `PadCompute` is absent.
- **Mac** exists and is genuinely live (bound to `ComputeCoordinator` over Multipeer + RealityKit), but several spec regions are missing (Thermals, Live throughput card, Unified-memory bar, Open-when-ready CTA, pipeline sub-labels).

---

## iPhone — `ComputeScreen.swift`

### P1 · wiring — Mac-handoff CTA is cosmetic; option selection has no effect
Spec CTA: `onClick={() => go(sel === 'mac' ? 'viewer' : 'viewer')}` — in the prototype both branches navigate, but in the shipping app this is the screen's entire purpose. `MacComputePane` + `ComputeCoordinator` already *listen* for a Multipeer hand-off, and `Sources/Shared/NetworkHandoffManager.swift` exists. Current Swift: `StButton(...) { model.go(.viewer) }` for both `sel == "mac"` and `sel == "local"`; choosing "Mac handoff" never starts a `NetworkHandoffManager` send, and the on-device vs Mac choice does not change downstream behavior.
Fix: when `sel == "mac"`, invoke `NetworkHandoffManager` to stream the scan archive to the listening Mac before/while navigating; when `sel == "local"` start the local `PhotogrammetryRunner`/processing path. Drive the handoff-card metrics (peer name, GB, Gbps) from the manager instead of literals.
Files: `Sources/iOS/Studio/Screens/ComputeScreen.swift`, `Sources/Shared/NetworkHandoffManager.swift`.

### P2 · token — "FASTEST" chip renders at 12px instead of spec 9px
Spec: `{opt.best && <Chip tone="accent" style={{ fontSize: 9 }}>FASTEST</Chip>}` — explicit `fontSize: 9`. Current `OptionCard` uses `StTextChip(text: "FASTEST", tone: .accent)`, and `StTextChip`/`StChip` are hard-wired to `.font(.sf(12, .semibold))` with no size override, so the badge is ~33% larger than designed.
Fix: add a compact size parameter to `StChip`/`StTextChip` (e.g. `font: CGFloat = 12`) and pass `9` for the FASTEST badge, or render a bespoke 9px capsule.
Files: `Sources/iOS/Studio/Screens/ComputeScreen.swift`, `Sources/Shared/DesignSystem/Primitives.swift`.

### P2 · token — header close-icon size 1px off
Spec phone header: back `Ic s={17}`, close `Ic s={16}`. `WizardHeader` → `CircleIconButton` renders every icon at fixed `StIcon(size: 17)`, so the close glyph is 17 instead of 16. Equivalent issue for the CTA: spec button child `Ic s={17}` while `StButton` derives icon size from font (`lg` ⇒ 16).
Fix: allow `CircleIconButton`/`StButton` to take an explicit icon size; set close to 16, CTA icon to 17. (Cosmetic.)
Files: `Sources/iOS/Studio/StudioChrome.swift`, `Sources/Shared/DesignSystem/Primitives.swift`.

### P2 · token — device-glyph shadow approximates `cardShadowLg` with a single layer
Spec `PhoneGlyph`/`MacGlyph` frames use `boxShadow: T.cardShadowLg` (two-layer: `0 2px 6px .05, 0 24px 60px .10`). Current `DeviceGlyph` uses one `.shadow(color: .black.opacity(0.1), radius: 12, y: 6)`, a smaller/tighter drop.
Fix: apply the two-layer `cardShadowLg` recipe (small contact + large ambient) for parity.
Files: `Sources/iOS/Studio/Screens/ComputeScreen.swift`.

---

## iPad — MISSING bespoke layout (`PadCompute` not implemented)

### P1 · missing-ipad — entire hub-and-spoke iPad compute screen is absent
`StudioRouter.swift` has no size-class branch (`case .compute: ComputeScreen()` only); on iPad the phone screen is shown centered via `readableContentWidth(720)`. The spec `PadCompute` is a first-class, structurally different layout that must be built:
- **Top bar** (`PadStatusBar`, content `top: 30`, padding 24): back button (38×38 fieldFill) + a two-line title block — overline `Step 4 of 4 · Compute pipeline` and `Where should we render?` (17px/700/-0.3) — and, on the right, **two action buttons**: secondary `Compute on iPad` (chip icon) and accent `Hand off to Mac` (laptop icon). (Note: phone has one bottom CTA; iPad has two top-right buttons.)
- **Giant content Card** (`radius 26`, padding 28, flex-fill), containing:
  - Header row: overline `Hub & spoke` (accentText) + headline `Capture here. ` / `Render there.` (42px/730/-1.6, second line accentText) + body copy "MultipeerConnectivity streams the raw scan to your Mac so the M-series Neural Engine renders without thermal limits — while your iPad stays cool." (14px text2, maxWidth 430, lineHeight 1.45).
  - A right **connection inset Card** (`inset`, radius 16, width 280): good dot + `Connected to "Adam's MBP"` (13/700), mono `peer · 192.168.1.42 · 1.2 Gbps` (10.5 text3), and three sm Stats `Ping 4 ms`, `Loss 0 %`, `Sent 1.1 GB` (accentText).
  - A middle **three-glyph streaming row**: iPad glyph (180×128, radius 16, label `iPad Pro M4`, sub `SCAN COMPLETE · 1.1 GB`) → a center column with a Glass pill `STREAMING · 58%` + `652 / 1124 MB`, a wide `HandoffArc width 420 height 90 progress 0.58`, and three mono chips `AES-256`, `multipeer`, `ETA 0:38` → MacBook glyph (200×128 wire HeroModel, base bar, label `MacBook Pro M4 Max`, sub `RECEIVING · NEURAL ENGINE`).
  - **Two BIG OptionCards side by side** (`gridTemplateColumns 1fr 1fr`, gap 14): `local` then `mac`, rendered with `big = true` (radius 20, padding 18) — note iPad orders local-first (phone orders mac-first).
Fix: add `PadCompute`-equivalent view, branch on `horizontalSizeClass == .regular` in the router (or inside `ComputeScreen`). Reuse `OptionCard` with a `big` flag, `HandoffArc`, `DeviceGlyph`, `StGlass`, `StChip`, `StStat`.
Files: `Sources/iOS/Studio/StudioRouter.swift`, `Sources/iOS/Studio/Screens/ComputeScreen.swift`, `Sources/iOS/Studio/StudioChrome.swift`.

---

## Mac — `MacComputePane` (`Sources/macOS/ContentView.swift`)

The pane is a real 3-pane dashboard bound to `ComputeCoordinator` (`pipeline rail | live preview | telemetry`). Live wiring is a plus; the gaps below are spec regions that are missing or diverge.

### P1 · missing-mac — entire "Thermals" telemetry section is missing
Spec telemetry: after Hardware + `Rule`, a `Label color={T.good}` **Thermals** block with three sm Stats: `SoC 58 °C` (good), `Fans 2400 rpm`, `Power 46 W`, then another `Rule`. Current `telemetry` goes Hardware → `Rule` → Transfer log with no Thermals section.
Fix: insert the Thermals block (good-toned label + 3 `StStat`) and a trailing `StRule` between Hardware and Transfer log.
Files: `Sources/macOS/ContentView.swift`.

### P2 · missing-mac — Hardware "Unified memory" bar missing (4th meter)
Spec Hardware has four bars: `Neural Engine 0.92 "38 TOPS"`, `GPU · 40-core 0.78 "76%"`, `CPU · 16-core 0.34 "34%"`, **`Unified memory 0.46 "22 / 48 GB"`**. Current renders only the first three.
Fix: add the 4th bar (value 0.46, color `text2`, right-label `22 / 48 GB`).
Files: `Sources/macOS/ContentView.swift`.

### P2 · missing-mac — pipeline-rail "Live throughput" inset Card missing
Spec pipeline rail ends with a `Card inset radius 14`: `Label color={T.accentText}` **Live throughput** + three sm Stats `Frames/s 184`, `Elapsed 2:38`, `Remaining 1:52`. Current `pipelineRail` ends with `Spacer()` after the stage list — no throughput card.
Fix: add `StCard(inset:, radius:14)` with the accent-toned label and three `StStat`s at the bottom of the rail.
Files: `Sources/macOS/ContentView.swift`.

### P2 · missing-mac — "Open when ready" CTA missing from telemetry panel
Spec telemetry ends with `Button kind="accent" full` → `cube` icon + **Open when ready** (`onClick go('viewer')`). Current telemetry ends with `Spacer()` and no button.
Fix: add a full-width accent `StButton(icon: "cube", title: "Open when ready")` that switches `MacSection` to `.viewer` (enabled when `stage == .done`).
Files: `Sources/macOS/ContentView.swift`.

### P2 · missing-mac — pipeline stages have no sub-labels
Spec each `PIPELINE` row has a mono sub-line: `334 frames · aligned`, `1.2M points · SfM`, `MVS · depth fusion`, `Poisson · 4.2M tris`, `8K PBR · albedo/normal`, `decimate · UV · USDZ`. `ComputeCoordinator.Stage` exposes only `label`; the rail renders just `Text(s.label)` with no sub.
Fix: add a `sub` string to `Stage` (or a parallel map) and render it as `font(.mono(11)).foregroundStyle(theme.text3)` under each label.
Files: `Sources/macOS/ComputeCoordinator.swift`, `Sources/macOS/ContentView.swift`.

### P2 · copy — livePreview Glass stat keys diverge
Spec bottom Glass stats: `Points 3.1M`, **`Depth maps 334`**, `Confidence 0.96` (good), **`Tris (est) 4.2M`**. Current uses keys `Frames` (bound to `receivedFrames`) and `Tris` — i.e. "Depth maps" → "Frames" and "Tris (est)" → "Tris".
Fix: rename to `Depth maps` and `Tris (est)` to match spec copy (keep the live binding for the value).
Files: `Sources/macOS/ContentView.swift`.

### P2 · copy — pipeline-rail label says "Apple Silicon" not "M4 Max"
Spec: `Label` **Pipeline · RealityKit on M4 Max**. Current: `StLabel(text: "Pipeline · RealityKit on Apple Silicon")`. (Generalization may be intentional; flagged for verbatim parity.)
Fix: align copy to spec, or derive the chip suffix from real hardware.
Files: `Sources/macOS/ContentView.swift`.

### P2 · copy/layout — top bar omits Library back + Rule, adds a Simulate button, and rewrites two chips
Spec top bar: `Library` back button (back icon + "Library") + vertical `Rule(height 22)` + accent dot + title + accent chip **Handoff from iPhone** + spacer + neutral chip **ETA 1:52**. Left padding `0 18px 0 84px` (84px traffic-light gutter). Current bar: accent dot + title + accent chip `Handoff · {peerName}` + spacer + neutral chip `etaText` ("Xs left"/"Idle"/"Complete") + an extra secondary **Simulate hand-off** button; no Library back button, no leading vertical Rule, no explicit 84px traffic-light gutter.
Fix: most differences are live/shell-justified (sidebar handles nav; dynamic peer/ETA are improvements), but for parity add the leading vertical `StRule` and ensure the 84px title-bar gutter; consider hiding the demo "Simulate hand-off" button behind a debug flag and matching the `Handoff from iPhone` / `ETA …` copy.
Files: `Sources/macOS/ContentView.swift`.

### P2 · token — active pipeline node lacks the accentSoft halo; live-preview status dot doesn't pulse
Spec: active stage node has `boxShadow: 0 0 0 3px ${T.accentSoft}` halo; the live-preview chip dot has `animation: st-pulse 1.4s infinite`. Current active node fills `accentSoft` but draws no 3px outer ring, and the chip dot is a static `Circle`.
Fix: add a 3px `accentSoft` ring overlay to the active node and a pulsing opacity animation to the preview dot.
Files: `Sources/macOS/ContentView.swift`.

### P2 · layout — pane widths and stage count differ
Spec: pipeline rail width **320**, telemetry width **300**; the rail lists exactly the **6** stages (`ingest…optimize`). Current: rail `width: 300`, telemetry `width: 280`; the rail iterates `Stage.allCases.filter { $0 != .waiting }`, which still includes `.done`, adding a 7th "Complete" row.
Fix: set rail to 320 / telemetry to 300; also filter `.done` out of the rail (treat it as terminal state) so only the 6 spec stages render.
Files: `Sources/macOS/ContentView.swift`.
