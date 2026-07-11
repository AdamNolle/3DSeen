# 3DSeen — Current Implementation Map (UI / design layer)

Read-only survey of the SwiftUI app as it exists on `main` (commit `aee8682`), produced to reconcile
against the design spec in `docs/design-spec/` and references in `docs/design-ref/`. No Swift was modified.

Scope covered: `Sources/Shared/DesignSystem/`, `Sources/iOS/Studio/` (+ `Screens/`),
`Sources/Shared/Studio/`, `Sources/macOS/`, both app entry points, and a high-level pass over
`Sources/iOS/Capture/*` and the `Sources/Shared/*` engines.

> Everything in the design layer is a faithful SwiftUI port of a React/JSX prototype (`studio/ds.jsx`,
> `studio/render.jsx`, `studio/screens/*.jsx`). Most on-screen numbers are hardcoded prototype data;
> only a few flows touch live engines (live capture, on-device splatting, model export, macOS compute).

---

## 1. Design tokens — `Sources/Shared/DesignSystem/Theme.swift`

**Mechanism.** A value-type token bag `struct Theme` (not a singleton, not an `ObservableObject`),
injected through the SwiftUI environment as `\.theme`. Screens read it with
`@Environment(\.theme) private var theme`. Default value is `.light` (`ThemeKey`, Theme.swift:191-200).

- `enum ThemeMode { case light, dark }` (Theme.swift:29).
- Two static instances: `Theme.light` (Theme.swift:107) and `Theme.dark` (Theme.swift:142), plus
  `Theme.of(_ mode)` (Theme.swift:177).
- Light/dark is a **manual in-app toggle**, *not* system-`colorScheme`-driven. iOS holds it in
  `StudioModel.dark` (default `false`) and applies `.preferredColorScheme(...)` at the root
  (StudioRouter.swift:48,59). macOS holds it in `ContentView.dark` `@State` with a sidebar toggle.

**Token names (all `Theme` stored properties).** Grouped exactly as in the file:

| Group | Tokens |
|---|---|
| surfaces | `canvas`, `bg`, `bgInset`, `card`, `card2` |
| text | `ink`, `text2`, `text3`, `text4`, `onAccent` |
| structure | `line`, `lineStrong`, `fieldFill`, `fieldFillHi` |
| accent (cobalt) | `accent`, `accentText`, `accentSoft`, `accentLine` |
| status | `good`, `goodSoft`, `warn`, `warnSoft`, `bad`, `badSoft` |
| glass | `glassFill`, `glassBorder`, `glassShine` |
| primary button | `primaryFill`, `primaryText` |
| charts | `grid`, `axis` |
| computed gradients | `stage` (LinearGradient, Theme.swift:88), `shellBackground` (RadialGradient, Theme.swift:97) |

**Representative color values** (light → dark):
`bg` #F6F5F2 → #161619 · `card` #FFFFFF → #1F1F25 · `ink` #1B1B1D → #F3F2F5 ·
`accent` #2D68F0 → #5E9BFF (cobalt) · `good` #1E8E5A → #34C77B · `warn` #B6791D → #E0A53F ·
`bad` #C53B30 → #FF6B5E. Most text/line/fill tokens are alpha tints of ink/white via the
`Color.ink(r,g,b,a)` helper (Theme.swift:22) and `Color(hex:)` (Theme.swift:11).

**Type tokens.** `Theme.sf = "SF Pro Display"`, `Theme.mono = "SF Mono"` (Theme.swift:84-85) are declared
but **unused**: the actual helpers `Font.sf(size,weight)` and `Font.mono(size,weight)` (Theme.swift:204-213)
fall back to `.system(...)` / `.system(..., design: .monospaced)`. Numeric readouts use `.monospacedDigit()`.

**`Stone` palette** (Theme.swift:182) — theme-independent warm-stone colors for rendered 3D objects:
`hi` #ECE4D6, `mid` #BFA98C, `lo` #6B5C49, `deep` #372E24.

---

## 2. Components / primitives — `Primitives.swift` + `LiquidGlass.swift`

All namespaced `St*` to avoid colliding with SwiftUI. Every requested archetype exists:

| Archetype | Type | Init params | Renders |
|---|---|---|---|
| Glass | `StGlass<Content>` + `.liquidGlass()` modifier (LiquidGlass.swift:80-97) | `radius`, `tone: .auto/.dark`, `shine` | Translucent `.ultraThinMaterial` lens + fill + top sheen + inner shade + rim + shadows. `.dark` tone darkens for over-camera legibility. |
| Card | `StCard<Content>` (Primitives.swift:42) | `radius=20`, `pad=0`, `elevated=false`, `inset=false` | Solid `card`/`bgInset` surface, hairline border, elevation shadow. |
| Button | `StButton` (Primitives.swift:71) | `title`, `kind` (primary/accent/secondary/ghost/glass), `size` (lg/md/sm), `icon?`, `full`, `action` | Capsule button; fg/bg per kind; optional leading `StIcon`. |
| Segmented | `StSegmented` (Primitives.swift:174) | `options:[(value,label)]`, `@Binding value`, `size` | Pill segmented control. **Defined but never used by any screen.** |
| Toggle | `StToggle` (Primitives.swift:208) | `@Binding on` | 50×30 pill switch, animated; on-tint = `good`. |
| Chip | `StChip<Content>` (Primitives.swift:234) + `StTextChip` (Primitives.swift:263) | `tone` (neutral/accent/good/warn/bad); StTextChip adds `text`,`icon?` | Capsule pill with tone-based bg/fg/border. |
| Meter | `StMeter` (Primitives.swift:277) | `value`, `color?`, `track?`, `height=6` | Horizontal progress bar. **Used only on macOS.** |
| Ring | `StRing` (Primitives.swift:298) | `value`, `size=72`, `stroke=7`, `color?`, `label?`, `sub?` | Trimmed-circle progress ring with centered label/sub. |
| Stat | `StStat` (Primitives.swift:138) | `k`, `v`, `unit?`, `color?`, `size` (xl/lg/md/sm), `align` | Keyed numeric readout (mono overline + bold value). |
| Label | `StLabel` (Primitives.swift:122) | `text`, `color?` | Uppercased mono overline, tracked. |
| Rule | `StRule` (Primitives.swift:336) | `vertical=false` | 0.5pt hairline divider. |
| Icon | `StIcon` (Primitives.swift:8) | `name`, `size=18`, `color?`, `weight` | Maps ~60 prototype icon names → SF Symbols via a static dict (Primitives.swift:14-31). |

**Missing primitives** (faked inline where needed): no text-field / input primitive (the Library search
bar is a static `Text` label, LibraryScreen.swift:47-54); no slider primitive (QualityScreen builds a
bespoke scale selector); no tab-bar / nav-bar primitive (navigation is bespoke per screen). Dark-glass
viewfinder helpers (`DLabel`, `DarkTelemetry`) live in ViewfinderScreen, not the shared layer.

---

## 3. Render helpers — `StudioRender.swift` (Canvas/Shape art, no real 3D)

`Sources/iOS/Studio/StudioRender.swift` (404 lines). Every requested helper exists:

- `Stage<Content>` (line 9) — neutral studio backdrop card for 3D content.
- `HeroModel` (line 44) — the "hero 3D model": a **2D `Canvas` illustration of a classical bust**
  (`material: pbr/wire/metal/matte`). There is **no SceneKit/RealityKit geometry** behind it.
- `CoverageSphere` (line 122) — viewfinder coverage globe; `covered`/`partial` wedge sets are **hardcoded**.
- `CoverageDome` (line 170) — review coverage dome with numbered dropout pins from `[Dropout]`.
- `Spark` (line 226) — sparkline. **Defined but unused by any screen.**
- `Histogram` (line 262) — synthetic RGB luma histogram. **Defined but unused.**
- `FrameStrip` (line 304) — frame thumbnail strip with rejected frames. **Defined but unused.**
- `ScanThumb` (line 342) — library tile: Canvas stone object + mode chip + name/meta label.
- `ScanTone.pair(_)` (line 28) — tone-name → stone color pair.

> **Duplication:** `Sources/iOS/Studio/StudioRender.swift` and `Sources/Shared/Studio/StudioRender.swift`
> are near-identical (only whitespace / `= nil` defaults / `Set` literal spacing differ). Same story for
> `SampleData.swift`. See §8.

---

## 4. Routing — `StudioRouter.swift`

- `enum StudioScreen: String, CaseIterable` (StudioRouter.swift:7) — the 10-screen enum, each with a
  `title`: `library, mode, briefing, viewfinder, quality, review, compute, viewer, export, settings`.
- `final class StudioModel: ObservableObject` (StudioRouter.swift:26): `@Published screen` (default
  `.library`), `@Published dark`, a `flow` array (the natural walkthrough order, identical to the enum
  order), and `go(_:)` (animated, `.easeOut 0.22`), `next()`, `prev()`.
- `struct StudioRoot` (StudioRouter.swift:45) owns the `StudioModel`, paints `theme.bg`, and switches
  `currentScreen` in a `switch` (StudioRouter.swift:62). Each screen is `.id(model.screen)` so it
  **re-mounts on change** with a `.opacity` transition; the model + `\.theme` are injected here.
- **Navigation model:** flat screen-replacement, **not** `NavigationStack`/`NavigationSplitView`.
  Screens advance by calling `model.go(.x)` from in-screen buttons. Wizard screens
  (`mode/briefing/quality/compute`) show a `WizardHeader` "Step n of 4" (StudioChrome.swift:36).
- **Entry point:** `ThreeDSeenApp` (Sources/iOS/3DSeenApp.swift) launches `StudioRoot()` and provides
  `.modelContainer(for: ScanSession.self)` + a `ProcessingStateMachine` env object.
  `Sources/iOS/ContentView.swift` is **legacy/dead** (an old blue-gradient mock; nothing references it).

Screen → file map: `library`→LibraryScreen, `mode`→ModePickerScreen, `briefing`→BriefingScreen,
`viewfinder`→ViewfinderScreen, `quality`→QualityScreen, `review`→ReviewScreen, `compute`→ComputeScreen,
`viewer`→ViewerScreen, `export`→ExportScreen, `settings`→SettingsScreen.

---

## 5. Per-screen summary (iOS)

### LibraryScreen.swift (168 lines) — `library`
- Header (`3DSeen · 42 scans`, settings cog → settings), big "Library" title, subtitle, a **non-functional
  search bar** (static `Text`, LibraryScreen.swift:47), `FeaturedCard`, filter pills, floating glass
  "New Scan" dock (→ `mode`).
- **Mixes live + sample data:** `@Query(sort: creationDate)` SwiftData `saved: [ScanSession]` renders a
  "Captured on this device" grid when non-empty; the lower grid always shows `SampleData.scans[1..<7]`.
  Featured = `saved.first` or `SampleData.scans[0]`.
- Hardcoded: "42 scans", "11.4 GB on device", FilterPills counts `(All 42, Object 28, Space 9, Landscape 5)`.
- Grid columns adapt 2→4 via `AdaptiveColumns` (see §6).

### ModePickerScreen.swift (170 lines) — `mode`
- `STUDIO_MODES` (4 static: Auto-Pilot / Object / Space / Landscape) with tags, blurbs, spec chips,
  tints. Big Auto tile + 2-col grid of the other three. `WizardHeader` step 1.
- **Most live-wired wizard screen.** Two CTAs: "Start Auto-Pilot / Continue" → `briefing` (design path),
  and "Skip walkthrough · live capture" which actually `stateMachine.send(.startCapture(liveMode))` and
  presents `CaptureCoordinatorView` in a `fullScreenCover`.
- On `.packagingScan` it **inserts a real `ScanSession`** into SwiftData (ModePickerScreen.swift:113-125)
  — but `sizeMB` is `Int.random(60...260)` and `triangles` is the literal `"4.2M"`.

### BriefingScreen.swift (145 lines) — `briefing`
- Readiness `StRing` 0.83 / "83", a 6-item `CHECKLIST` (**only first 4 shown**), and a 4-item `GUIDES`
  list (**only first 2 shown**). `WizardHeader` step 2. CTA → `quality`.
- 100% static. Hardcoded copy: "You're ready in 5 of 6", "1842 lux measured", "Nominal · 31 °C", etc.

### ViewfinderScreen.swift (264 lines) — `viewfinder`
- **A fully faked viewfinder, not a real camera.** `CameraFeed` is a `Canvas` bust illustration on a dim
  studio gradient; `ARBox` (corner brackets + caliper "14.2 cm"), `DarkTelemetry`
  (LUX 1840 / DIST 42cm / SHARP 0.94 / MOTION 34°/s — all literals), `coverageTile` (CoverageSphere 72%),
  coaching toast, and a shutter dock with hardcoded ETA. Dark Liquid Glass overlays throughout.
- Shutter → `review`. The **real** camera UI is the separate `CaptureCoordinatorView`, only reachable from
  ModePicker's "Skip walkthrough" — the wizard's own viewfinder never shows a live feed.

### QualityScreen.swift (198 lines) — `quality`
- `DETAIL_TIERS` (5 static: Preview→Raw, mapped to "Apple PhotogrammetrySession tiers"). Bespoke
  FAST↔ARCHIVE scale selector (custom dots over a gradient), a `TierCard` for the selection, and two
  collapsed alt-tier rows. `WizardHeader` step 3. CTA → `review`. 100% static.

### ReviewScreen.swift (96 lines) — `review`
- "Capture complete" chip, `CoverageDome(drops: SampleData.dropouts)`, and dropout rows (each with a
  "Retake" → `viewfinder`). CTAs: "Retake all" → `viewfinder`, "Compute now" → `compute`.
- Data: `SampleData.dropouts` (3 items). Hardcoded header "Coverage 92% · 340 frames".

### ComputeScreen.swift (177 lines) — `compute`
- Handoff card: `DeviceGlyph(phone)` ↔ `HandoffArc(0.62)` ↔ `DeviceGlyph(mac)`, then two `OptionCard`s
  ("Mac handoff" best / "On-device") with static stat rows. `WizardHeader` step 4.
- **No real handoff is triggered** — the CTA simply navigates to `viewer`. All stats (ETA 1:52, 3.6×,
  battery, "MULTIPEER · 1.2 Gbps") are literals. (Real Multipeer handoff lives in `NetworkHandoffManager`
  + the macOS receive side, not wired to this screen.)

### ViewerScreen.swift (180 lines) — `viewer`
- `Stage { HeroModel(material:) }` backdrop, vertical `ToolRail` (orbit/measure/pin/splat/light),
  `MeasureOverlay` when measure is active, a bottom glass inspector (`StStat` Tris/Tex/PSNR/Scale +
  `MaterialPicker`), and AR / Export buttons.
- Selecting the **`splat`** tool opens `SplatViewerScreen` (the real on-device Metal renderer) via
  `fullScreenCover`. The **AR button is a no-op `{}`** (ViewerScreen.swift:86). Stats are hardcoded
  ("4.2M", "4K", "38.7", "14cm").

### ExportScreen.swift (297 lines) — `export`
- Bottom-sheet `StGlass` with a 3-stage `ExportFlow` state machine (`config → progress → done`).
- **Performs a real export:** `start()` runs `ModelExporter().exportSample(to:)` off-main, writing an
  actual file via ModelIO; a `Timer` animates a *fake* progress bar in parallel; `done` shows the real
  written URL and offers a real `UIActivityViewController` `ShareSheet`. Falls back to placeholder copy
  if `exportedURL` is nil. Format list = `SampleData.exportFormats`; destinations/options are static and
  the option toggles aren't persisted.

### SettingsScreen.swift (171 lines) — `settings`
- Profile card ("Adam Nolle · 3DSeen STUDIO v2.4.1 · PRO"), four static `SETTINGS` sections of rows
  (value rows + `StToggle` rows), and a "Connected" devices list (2 static).
- **All static.** Toggle rows use per-row `@State private var on` seeded from the literal — **not persisted**
  anywhere (UserDefaults/SwiftData), and reset on remount. No control here is wired to `StudioModel.dark`,
  so **dark mode is unreachable at runtime on iOS** (see §8).

---

## 6. Device adaptivity (iPad)

There is **no bespoke iPad layout** — no `NavigationSplitView`, sidebar, columns view, or regular-width
screens. iPad gets the same iPhone screens with **width reflow only**, via two helpers in
`StudioChrome.swift`:

- `readableContentWidth(_ max)` (StudioChrome.swift:70-86) — on `.regular` horizontal size class it caps
  and centers the content frame; **pass-through on compact (iPhone)**. Used by most scroll screens
  (Library uses `980`, others the `720` default). Verbatim:
  ```swift
  func body(content: Content) -> some View {
      if hSize == .regular { content.frame(maxWidth: max).frame(maxWidth: .infinity) }
      else { content }
  }
  ```
- `AdaptiveColumns.count(_:compact:regular:)` (StudioChrome.swift:93-97) — returns `regular` count on
  `.regular`, else `compact`. Only LibraryScreen uses it (`compact: 2, regular: 4`, LibraryScreen.swift:15).
- `BottomCTA` caps its label at `maxWidth: 540` on all devices (StudioChrome.swift:54).
- ⚠️ A second helper `View.adaptiveColumnCount(_:_:)` (StudioChrome.swift:89) **always returns `compact`** —
  looks like a dead/buggy stub; nothing uses it.

Net: iPad = centered, width-capped iPhone screens with a 4-wide library grid. No split navigation, no
master/detail, no regular-width-specific composition.

---

## 7. macOS app — `Sources/macOS/ContentView.swift` (510 lines)

A genuine desktop app (not a mirror of the iOS wizard). `ThreeDSeenMacApp` → `ContentView` → `MacShell`,
reusing the shared design system + render helpers. `.frame(minWidth: 1120, minHeight: 720)`,
`.hiddenTitleBar`, `.modelContainer(for: ScanSession.self)`.

- **Sidebar** (248pt, ContentView.swift:728): logo + version, 4 nav items, a Storage `StCard(inset)`
  ("11.4 / 256 GB"), and a **dark/light appearance toggle** (the macOS dark toggle that iOS lacks). The
  Compute item shows a live activity dot when `compute.isProcessing`.
- `enum MacSection { library, viewer, compute, export }` (ContentView.swift:685) — **no Settings pane.**

| Pane | Completeness | Notes |
|---|---|---|
| `MacLibraryPane` | Static mock | Toolbar + hero `StCard` (Stage+HeroModel + "Celestial Bust" stats). All sample data. |
| `MacViewerPane` | Static mock | Stage+`HeroModel(material:)` + inspector: Geometry `StStat`s, `MAC_MATERIALS` override picker, `SampleData.measurements`. |
| `MacComputePane` | **Live** | Bound to a real `ComputeCoordinator` `@StateObject`: pipeline-stage rail, `StMeter` progress, hardware bars, transfer log, and a `simulate()` button. This is the real spoke that receives iPhone hand-offs over Multipeer and runs RealityKit `PhotogrammetrySession`. |
| `MacExportPane` | **Live** | Stage+HeroModel preview + format config; `export()` writes a real file via `ModelExporter().export(asset:to:outputURL:)` into Downloads and reveals it in Finder (`NSWorkspace`). |

So: Compute + Export are wired to real engines; Library + Viewer are static design mocks; there is no
Settings pane on macOS.

---

## 8. Gaps / risks

**Build-breaking (latent).**
- 🔴 **Duplicate source files.** `Sources/iOS/Studio/SampleData.swift` and
  `Sources/iOS/Studio/StudioRender.swift` are untracked (`??`) near-duplicates of the tracked
  `Sources/Shared/Studio/` versions. `project.yml` globs **both** `Sources/iOS` *and* `Sources/Shared`
  into the `3DSeen-iOS` target (project.yml:20-22), so after a `xcodegen generate` the iOS target gets two
  definitions of `SampleData`, `ScanItem`, `ExportFormatInfo`, `Measurement`, `Dropout`, `Stage`,
  `HeroModel`, `CoverageSphere`, `CoverageDome`, `Spark`, `Histogram`, `FrameStrip`, `ScanThumb`, … →
  redeclaration errors. It currently builds only because the committed `.pbxproj` predates these files
  (it references neither — `grep` count 0). The project's own build notes say xcodegen regen is required,
  which would trip this. **Delete the iOS copies or exclude one folder per target.**

**Wiring / placeholder.**
- 🟠 **Dark mode unreachable on iOS.** `StudioModel.dark` exists and is honored at the root, but **no iOS
  control toggles it** (Settings has no appearance row). Only macOS exposes the toggle.
- 🟠 **Faked viewfinder.** The wizard `ViewfinderScreen` is a `Canvas` illustration with literal telemetry;
  the real camera (`CaptureCoordinatorView` → Object/Room/Landscape engines) is only reachable via
  ModePicker's "Skip walkthrough" and is never part of the polished wizard flow.
- 🟠 **ComputeScreen handoff is cosmetic** — the CTA just navigates to `viewer`; no `NetworkHandoffManager`
  / Multipeer send is invoked from iOS.
- 🟠 **Settings is non-persistent** — toggles are per-row `@State`, reset on navigation; nothing reads/writes
  UserDefaults or SwiftData.
- 🟠 **Library search bar is a static label** (no `TextField`, no filtering logic; FilterPills don't filter).
- 🟡 **ViewerScreen "AR" button is a no-op** (`{}`); stats hardcoded; version "v2" literal.

**Dead / unused code.**
- 🟡 `Sources/iOS/ContentView.swift` is unused legacy (old gradient mock; app launches `StudioRoot`).
- 🟡 Render helpers `Spark`, `Histogram`, `FrameStrip` are defined but referenced by **no screen**.
- 🟡 Primitive `StSegmented` is defined but used by **no screen**. `StMeter` is used only on macOS.
- 🟡 `View.adaptiveColumnCount(_:_:)` always returns `compact` (effectively dead/buggy).

**Data fidelity.**
- 🟡 Nearly every metric is a hardcoded prototype constant (lux 1842, readiness 83, coverage 92% /
  340 frames, 4.2M tris, PSNR 38.7, ETA 1:52, 1.2 Gbps, "42 scans / 11.4 GB", etc.).
- 🟡 The only live persistence is ModePicker inserting a `ScanSession` on capture finish, but with
  `sizeMB = random(60...260)` and `triangles = "4.2M"` literal.
- 🟡 `Theme.sf`/`Theme.mono` named-font constants are unused (helpers use the system font); minor visual
  drift risk vs. a spec that calls for SF Pro Display / SF Mono specifically.
- 🟡 Two near-identical `SampleData.swift` copies can silently drift (already differ cosmetically).

**Engines (high level — real, just not surfaced in the wizard UI).**
- `Sources/iOS/Capture/*`: `ObjectCaptureEngine` (RealityKit ObjectCapture), `RoomCaptureEngine`
  (RoomPlan + `RoomCaptureController`), `LandscapeCaptureEngine` (ARKit VIO) — all real `UIViewRepresentable`
  hosts behind `CaptureCoordinatorView`.
- `Sources/Shared/*`: `ProcessingStateMachine` (full `AppState`/`AppEvent` FSM), `NetworkHandoffManager`
  (MultipeerConnectivity send/receive), `PhotogrammetryRunner` (RealityKit `PhotogrammetrySession`),
  `ModelExporter` (ModelIO export to USDZ/USD/OBJ/STL/PLY/glTF/FBX), `GaussianSplatGenerator` +
  `SplatPLYWriter` (real on-device 3DGS `.ply` generation), `AutoPilotVisionManager` (CoreML/Vision scene
  classification), `LocalQueueManager`, `AIPBRMaterialEstimator`, `MaterialOverrideLibrary`.
- `Sources/iOS/Studio/GaussianSplat.swift`: real `MetalSplatter` `SplatRenderer` in an `MTKView` with
  orbit/zoom gestures and `.ply`/`.splat` file import — the genuine on-device-splatting differentiator.
  Note its "Generate sample" path renders a demo Fibonacci-sphere cloud, not capture-derived splats.
