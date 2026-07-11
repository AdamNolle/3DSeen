# Viewer screen — fidelity audit

Spec: `docs/design-spec/viewer.md` + ground-truth `docs/design-ref/screens/viewer.jsx`
(MaterialPicker + Mac variant are VERBATIM; iPhone/iPad chrome is mostly INFERRED/PATTERN).
Foundation tokens: `docs/design-spec/00-foundation.md`.

Implementations audited:
- iPhone/iPad: `Sources/iOS/Studio/Screens/ViewerScreen.swift` (single layout, no size-class branch).
- Mac: `MacViewerPane` in `Sources/macOS/ContentView.swift:339-413`.

Shared primitives used by fixes: `St*` in `Sources/Shared/DesignSystem/Primitives.swift`
(`StButton`, `StStat`, `StLabel`, `StSegmented(options:[(value,label)],value:)`, `StChip`, `StRule`, `StIcon`),
`StGlass`/`liquidGlass` in `LiquidGlass.swift`, `Stage`/`HeroModel` in `Sources/Shared/Studio/StudioRender.swift`,
`SampleData.measurements` in `Sources/Shared/Studio/SampleData.swift`.

---

## iPhone — `PhoneViewer` vs `ViewerScreen`

Generally close, but the verbatim measure callout is missing, the title pill carries extra content,
the legibility scrim is gone, and the data is hardcoded.

### P1

- **Measure callout pill is missing (VERBATIM copy + component).**
  Spec: when `tool === 'measure'` the *only* overlay is a `Glass radius={10}` (`padding 5px 10px`) at
  `left 52, top 326` containing mono **"14.20 cm"** (`12px / 700 / T.accentText`).
  Current (`ViewerScreen.swift:28-31`) instead renders an invented `MeasureOverlay` dashed leader line
  (not present in `PhoneViewer` at all) and **never shows the "14.20 cm" callout**.
  Fix: in the `tool == "measure"` branch add a `StGlass(radius: 10)` overlay positioned near the chin/crown
  with `Text("14.20 cm").font(.mono(12, .bold)).foregroundStyle(theme.accentText)` (pull the value from
  `SampleData.measurements[0]`). Keep the leader line as an optional enhancement, but the pill is required.

- **Title + all stats are hardcoded mock, not bound to a scan/model.** (also Mac — see ALL)
  `ViewerScreen` injects `@EnvironmentObject model: StudioModel` but reads nothing from it. Title
  `"Celestial Bust"` (`:43`), `"v2"` (`:71`), and stats `Tris 4.2M / Tex 4K / PSNR 38.7 / Scale 14cm`
  (`:74-77`) are literals. There is no "selected scan" plumbing.
  Fix: add a `selectedScan: ScanItem` (default `SampleData.scans[0]`) to `StudioModel`, drive the title and
  the `Tris`/`Tex`/`Scale` stats from it; bind PSNR/version to real geometry once compute output exists.

- **"AR" button is a no-op.** `ViewerScreen.swift:86` — `StButton(title: "AR", … ) {}` has an empty action.
  An AR preview already exists (`Sources/iOS/Preview/InstantARPreviewView.swift`).
  Fix: present `InstantARPreviewView` / AR Quick Look from the AR button (and from the iPad/Mac AR tool).

### P2

- **Title pill diverges from spec.** Spec phone center pill (`viewer.jsx:97`) is a `Glass radius=999`,
  `flex:1`, `textAlign:center`, containing only **"Celestial Bust"** at `14px / 700 / ls -0.3`.
  Current (`:40-48`) left-aligns the text and adds a `Circle(theme.good)` status dot **and** a
  `"· 4.2M · Full"` mono meta string (that dot+meta belongs to the iPad meta chip / Mac toolbar, not the
  phone pill), and uses `.semibold` / `tracking(-0.2)`.
  Fix: pill content = centered `Text("Celestial Bust").font(.sf(14, .bold)).tracking(-0.3)`, no dot, no meta.

- **Legibility scrim missing.** Spec layer 2 (`viewer.jsx:90`): top/bottom dark gradient over the stage
  `linear-gradient(180deg, rgba(0,0,0,.20), transparent 26%, transparent 72%, rgba(0,0,0,.24))`.
  Current has no scrim, hurting glass-chrome legibility over a light stage.
  Fix: add a non-interactive `LinearGradient` overlay above `Stage`, below the chrome.

- **Tool rail has an extra `splat` tool not in the design.** Spec phone rail (`viewer.jsx:103`) = 4 tools
  `orbit:cube, measure:ruler, pin:pin, light:light`. Current (`:58`) adds a 5th `splat`/`sparkle` tool whose
  only job is to open `SplatViewerScreen` via `fullScreenCover`. Reasonable as a real feature, but it
  diverges from the spec rail and uses a non-spec icon.
  Fix: either drop `splat` from the rail (open the splat viewer from elsewhere) or document it as an
  intentional superset; match spec ordering `orbit/measure/pin/light` for the canonical four.

- **Tool-rail button metrics off.** Spec `ToolRail` button is `44×44`, `Ic s=20` (canonical Mac rail
  confirms `42×42 / radius 11 / Ic s20`). Current `ToolRail` (`:117-119`) uses `40×40`, icon size `19`.
  Fix: button `44×44`, `StIcon(size: 20)`, keep radius 13 / glass radius 18 / padding 6.

- **Bottom action row width ratio wrong.** Spec (`viewer.jsx:124-127`): AR `Button flex:1`, Export
  `Button flex:1.5` (Export ~1.5× wider) with `Ic s=16`. Current (`:85-88`) sets `full: true` on both →
  equal 50/50 widths, and `StButton` renders the icon at the md font size (15), not 16.
  Fix: wrap in a `GeometryReader`/proportional layout so Export is ~1.5× AR (or give Export `layoutPriority`
  + an explicit min width); bump the inline icons to 16.

- **Top-bar icon sizes slightly off.** Right export button uses `StIcon size 17` (`:50`); spec right icon is
  `s=18` (matching the verbatim back `s=18`). Minor token drift. Fix: size 18.

---

## iPad — `PadViewer`  (MISSING — P1 `missing-ipad`)

There is **no bespoke iPad layout**. `StudioRoot` (`StudioRouter.swift:71`) renders `ViewerScreen()` for all
size classes; `ViewerScreen` has no `horizontalSizeClass`/`UIDevice` branch, no `env` state, no
`readableContentWidth`. On iPad the immersive **phone** layout stretches edge-to-edge — the entire
`PadViewer` composition is absent.

Build `PadViewer` per spec (`viewer.jsx:134-200`):

- **Top bar** (`top 36, left/right 18`, gap 10): glass round `40×40` back → `library`;
  glass title pill `Celestial Bust` (`15 / 700 / -0.3`); glass meta chip mono **"FULL · 4.2M · 184 MB"**
  (`11 / text2`); `Spacer`; `StButton(kind:.glass, size:.sm, icon:"airdrop")` **"AirDrop"**;
  `StButton(kind:.accent, size:.sm, icon:"export")` **"Export"** → `export`.
- **Left tool rail** (`top 96, left 18`): `ToolRail` **with labels**, 5 items
  `orbit/Orbit, measure/Measure, pin/Pin, light/Light, ar/AR` (button height 50 when labeled, label `9 / 600`).
  Note: current `ToolRail` has no `labels` parameter — extend it.
- **Measure callouts** (only when `tool == "measure"`): two glass pills at `left 358,top 350` ("14.20 cm")
  and `left 700,top 305` (e.g. "21.8 cm").
- **Right inspector column** (`top 96, right 18, bottom 18`, **width 326**, gap 12), three `Glass radius=20`
  `padding 16` cards:
  1. Geometry — `StLabel("Geometry", color: accentText)`, grid `1fr 1fr` gap 14:
     `Triangles 4.2M`, `Vertices 2.1M`, `Textures 4K PBR`, `PSNR 38.7` (all `.sm`).
  2. Material override — `StLabel("Material override")` + `MaterialPicker(value: $mat)` (non-compact).
  3. Measurements (flex 1) — `StLabel("Measurements · 3 pins", color: good)`, iterate
     `SampleData.measurements`: label `text2 13`, value `"{value} {unit}" 14 / 700 / ink`, `0.5px` line
     between rows (suppress border on `M01`).
- **Bottom env bar** (`bottom 18, left 110, right 360`, centered): `Glass radius=999 padding 6` wrapping
  `StSegmented(size:.sm, options:[Studio,Sunset,Soft,Field], value:$env)`; add `@State env = "Studio"`.

Fix: gate on `horizontalSizeClass == .regular` (or split into `PhoneViewer`/`PadViewer` subviews) and render
the above instead of the reflowed phone layout.

---

## Mac — `MacViewer` vs `MacViewerPane`  (this spec variant is VERBATIM)

`MacViewerPane` exists but only renders **two** panes (stage + 320 inspector). The spec is a **3-pane**
desktop with a left tool rail, a richer toolbar, and stage overlays — several regions are missing.

### P1 (`missing-mac`)

- **Left tool rail (width 64) is absent.** Spec body (`viewer.jsx:221-228`): a `64`-wide rail
  (`borderRight 0.5px line`, `card2`) with 7 buttons `42×42 / radius 11`, bg `accent` when active, `Ic s=20`:
  `orbit:cube, measure:ruler, pin:pin, layers:layers, light:light, ar:scan, slice:focus`.
  Current `MacViewerPane.body` (`ContentView.swift:355-360`) jumps straight from `Stage` to `inspector`.
  Fix: add `@State tool` + the 64-wide rail as the first child of the body `HStack`.

- **Stage floating env bar is absent.** Spec (`viewer.jsx:234-238`): bottom-center
  `Glass radius=16 padding 6` wrapping `StSegmented(size:.sm, options:[Studio,Sunset,Soft,Field], value:"Studio")`.
  Current stage (`:356-357`) is bare.
  Fix: overlay the segmented env bar at the bottom-center of the stage `ZStack`.

- **Toolbar view-mode Segmented is absent.** Spec toolbar (`viewer.jsx:216`):
  `Segmented size="sm" options=['Inspect','AR','Compare','Slice'] value="Inspect"`.
  Current toolbar (`:345-351`) has no mode switcher.
  Fix: add `StSegmented(size:.sm, options:[Inspect,AR,Compare,Slice], value:)` before the `Spacer`.

### P2 (`missing-mac` / copy / component)

- **Stage status chip missing.** Spec (`viewer.jsx:233`): top-left `Chip tone="neutral"` with
  `Ic cube s13` + **"Orbit · ⌘-drag to pan"**. Current stage has no overlay.
  Fix: overlay `StChip(tone:.neutral){ StIcon("cube",13); Text("Orbit · ⌘-drag to pan") }` top-left.

- **Toolbar Library button / Rule / AirDrop / "Export…" missing.** Spec toolbar (`viewer.jsx:210-218`) has a
  left `Library` back button (`height 30, fieldFill, radius 8, Ic back s15`) + vertical `Rule`, and on the
  right `Button kind="ghost" "AirDrop"` (`Ic airdrop s15`) + `Button kind="accent" "Export…"` (`Ic export s15`).
  Current (`:350`) replaces all of this with a single `StChip "AR Quick Look ready"`. (Library back is
  acceptable to omit since the Mac app navigates via its sidebar, but **AirDrop is absent app-wide** and the
  in-context **Export…** action is gone.)
  Fix: add an `Export…` (accent, sm) action that switches to the Export section, and an `AirDrop` (ghost, sm)
  action; keep the AR-ready chip only if there is room.

- **Measurements action row missing.** Spec inspector (`viewer.jsx:267-270`): below the rows, a button row
  `Button secondary sm "Add pin"` (`Ic plus s15`) + `Button secondary sm "CSV"` (`Ic download s15`).
  Current inspector (`:395-406`) ends after the rows. Fix: add the two `StButton(kind:.secondary,size:.sm)` (flex 1 each).

- **Geometry stats copy wrong.** Spec (`viewer.jsx:246`): `Triangles 4.2M, Vertices 2.1M, Textures "4K PBR",
  File size "184 MB"`. Current (`:370-373`): `Triangles 4.2M, Vertices 2.1M, UV islands 46, Watertight Yes` —
  the 3rd and 4th stats are different metrics.
  Fix: change to `Textures "4K PBR"` and `File size "184 MB"`.

- **Material picker reimplemented + divergent.** Spec uses the shared `MaterialPicker` (VERBATIM): `30×30`
  swatch, button radius 14, selected = `fieldFillHi` + `inset 0 0 0 1px accentLine`. Current defines a
  separate `MAC_MATERIALS` array (duplicate of `STUDIO_MATERIALS`) and an inline picker (`:379-392`) with a
  `28×28` swatch, radius 12, and **no** selected accentLine ring.
  Fix: reuse `MaterialPicker(value: $mat)` from `ViewerScreen.swift`; delete `MAC_MATERIALS` (dead duplicate).

- **Measurement pin index style wrong.** Spec (`viewer.jsx:261`): a `20×20` round chip, bg `accentSoft`,
  color `accentText`, `10 / 700`, showing the **numeric** id (`M01` → "1"). Current (`:399`) uses
  `StTextChip(m.id, tone:.accent)` rendering the full **"M01"** capsule.
  Fix: render a `20×20` `Circle().fill(accentSoft)` with `Text(numericId).font(.sf(10,.bold)).foregroundStyle(accentText)`.

---

## All targets

- **Viewer data is static mock everywhere (wiring).** iPhone and Mac both hardcode title/stats/measurements;
  nothing reads a selected scan or real compute geometry. Once a "current scan" is plumbed through
  `StudioModel` (iOS) / the Mac sidebar selection, drive Geometry/Material/Measurements from it
  (`SampleData` is the interim source; `MEASUREMENTS` already exists as `SampleData.measurements`).

- **Icon-only controls lack accessibility labels (a11y, P2).** The phone top-bar back/export buttons
  (`ViewerScreen.swift:36-52`), the `ToolRail` buttons (`:114-121`), and the Mac rail buttons (once added)
  are `Button { } label: { StIcon … }` with no `.accessibilityLabel`. VoiceOver reads nothing meaningful.
  Fix: add `.accessibilityLabel("Library")`, `"Export"`, `"Orbit"`, `"Measure"`, etc.
