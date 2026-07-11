# Export & Share — fidelity audit

Spec: `docs/design-spec/export.md` · Source of truth: `docs/design-ref/screens/export.jsx` (`PhoneExport`, `PadExport`, `MacExport`)
Current Swift: `Sources/iOS/Studio/Screens/ExportScreen.swift` (iPhone only) · `Sources/macOS/ContentView.swift` `MacExportPane` (lines 417–508)
Primitives: `Sources/Shared/DesignSystem/Primitives.swift` · Data: `Sources/Shared/Studio/SampleData.swift`

Verdict: the **iPhone** bottom-sheet flow is a high-fidelity port (config → progress → done, real `ModelExporter`).
The **iPad** bespoke centered two-pane modal (`PadExport`) is **entirely missing** — iPad gets the iPhone bottom sheet
(3 formats / 2 options) with no width handling. The **Mac** pane exists but is a stripped static config: it drops the
config→progress→done flow, Options, Destination, the preview stats glass, the standard toolbar (back button / traffic-light
inset / rule), the output path string, and ships a wrong CTA label. Plus a handful of mono-vs-sans token slips on iPhone.

---

## iPhone — `ExportScreen` (faithful, polish gaps)

### P2 · token — Progress/Done sub-lines render in SF, spec is mono (`st-num`)
- Spec `ProgressView`: sub `<div className="st-num" style={{ fontSize: 13 … }}>` → mono/tabular. Current
  `ExportScreen.swift:243-244` uses `.font(.sf(13))`.
- Spec `DoneView`: sub `<div className="st-num" style={{ fontSize: 13.5 … }}>` → mono. Current `:272-278` uses `.font(.sf(13.5))`.
- Fix: change both to `.font(.mono(13))` / `.font(.mono(13.5))` so the size/phase/dest readout is monospaced like the prototype.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`

### P2 · interaction/copy — success path replaces "Export again" with "Share file" and rewrites the done sub-copy
- Spec `DoneView`: always two buttons — secondary **"Export again"** (`Ic refresh`) → `reset`, accent **"Done"** → `go('library')`;
  sub-copy verbatim **"Celestial Bust{format.ext} · {format.size} · sent to {dest.l}"**.
- Current `:271-288`: when `exportedURL != nil` the secondary becomes **"Share file"** (opens `UIActivityViewController`) and the
  sub becomes **"\(url.lastPathComponent) written · sent to \(d.label)"** — so the spec's "Export again" reset path is unreachable
  on a successful real export. This is a deliberate real-export enhancement, but it diverges from the spec.
- Fix: keep the real share affordance but preserve the spec layout — show **"Export again"** as the secondary and surface Share as
  an extra/tertiary action (or a small share glyph), and restore the spec sub-copy as the default, keeping the URL variant only as a
  detail line. Don't drop the reset path.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`

### P2 · component — "BEST" chip is full-size, spec shrinks it
- Spec `FormatRow`: `{f.best && <Chip tone="accent" style={{ fontSize: 9, padding: '2px 6px' }}>BEST</Chip>}` — a 9px chip with
  2×6 padding. Current `:191` uses `StTextChip(text: "BEST", tone: .accent)`, which renders at the chip default (12px font,
  10×4 padding) — visibly oversized next to the 14px ext.
- Fix: add a size/compact parameter to `StChip`/`StTextChip` (font 9, padding `.horizontal 6 / .vertical 2`) and use it here, or
  inline a small accent capsule for BEST.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`, `Sources/Shared/DesignSystem/Primitives.swift`

### P2 · token — selected `DestRow` cell is missing its accent drop shadow
- Spec `DestRow`: selected tile `boxShadow: 0 4px 14px ${T.accentSoft}`. Current `DestRow` (`:219-222`) only swaps fill/stroke; no
  shadow on the selected `56×56` tile.
- Fix: add `.shadow(color: theme.accentSoft, radius: 7, y: 4)` on the selected rounded-rect.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`

### P2 · token — Ring center label truncates instead of rounding; Ring track color drift
- Spec `Ring … label={Math.round(pct)}`. Current `:240` passes `"\(Int(pct))"` which truncates (e.g. 99.6 → "99" not "100").
  Fix: `"\(Int(pct.rounded()))"`.
- Shared `StRing` paints the track with `theme.fieldFillHi`; foundation §3 specifies Ring track color `line`. Minor, affects this
  progress ring. Fix in the primitive if exactness matters.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`, `Sources/Shared/DesignSystem/Primitives.swift`

### P2 · token — Done title weight overshoot; option rows miss the 2px horizontal inset
- Spec done title weight 720; current `:270` `.sf(18, .heavy)` (≈800). Spec option row padding is `8px 2px`; current `:153`
  uses only `.padding(.vertical, 8)` (no 2px horizontal). Both trivial.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`

### P2 · wiring — options & destination are decorative (export ignores them)
- The `opts` toggles (measure/bake) and `dest` selection feed only the UI; `start()` calls
  `ModelExporter().exportSample(to: format)` (`:60`) which ignores measurements/scale/color and the chosen destination. This
  matches the prototype's cosmetic intent, but if these are meant to be functional they need wiring (e.g. include measurement pins,
  route to AirDrop/iCloud/Files). Toggles are also not persisted.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`

---

## iPad — `PadExport` (MISSING bespoke layout — P1)

### P1 · missing-ipad — no centered two-pane modal; iPad shows the iPhone bottom sheet
- Spec `PadExport`: dimmed backdrop (`rgba(0,0,0,0.5)` dark / `rgba(20,20,30,0.32)` light) + `PadStatusBar tone="light"`, then a
  **centered `Glass radius=26` modal, width 880**, `st-modal-in`, `overflow hidden`, with:
  - Header (row, padding `16px 22px`, bottom hairline): `ModelBadge size=44`, title **"Export & Share"** + mono
    **"CELESTIAL BUST · FULL · 184 MB"**, `34×34` close → `viewer`.
  - config = **2-column grid (`1fr 1fr`, minHeight 420)**: left = live preview pane (`Stage`+`HeroModel 400×300`, top-right accent
    chip **"AR Quick Look ready"**) + 4-up `Stat` grid (Format/Size+unit MB/Tris 4.2M/Tex 4K) + **"Send to"** `DestRow`;
    right (scroll) = **"Format"** with **all 6** `FormatRow`s + **"Options"** with **all 4** option rows (borderTop on every row
    except `measure`) + spacer + CTA.
  - progress/done = a `minHeight 420` centered cell holding `ProgressView big` / `DoneView big`.
- Current: `StudioRouter` renders a single `ExportScreen()` for every size class (no regular-width branch); `ExportScreen` is a
  bottom sheet that on iPad stretches full-width and still shows only `prefix(3)` formats and `prefix(2)` options. None of the
  two-pane modal, preview pane, stats grid, all-6/all-4 sets, or `big` progress/done exist.
- Fix: add a `@Environment(\.horizontalSizeClass)` branch (or a dedicated `PadExportScreen`) that, on `.regular`, presents the
  centered 880-wide `StGlass(radius:26)` modal with the header + 2-column grid described above, reusing the existing
  `FormatRow`/`DestRow`/`ProgressView`/`DoneView` (add a `big` flag to the latter two for size 132 ring / larger badges). Show all 6
  `SampleData.exportFormats` and all 4 `EXPORT_OPTIONS` with internal-only dividers, plus the `Stat` row using
  `format.size.split(" ").first` for the value and `unit: "MB"`.
- Files: `Sources/iOS/Studio/Screens/ExportScreen.swift`, `Sources/iOS/Studio/StudioRouter.swift`

---

## Mac — `MacExport` vs `MacExportPane` (reduced static port)

### P1 · missing-mac — no config → progress → done flow on Mac
- Spec `MacExport`: the config rail swaps to `ProgressView big` (`stage==='progress'`) and `DoneView big`
  (`stage==='done'`), driven by the shared `useExportFlow` 180ms timer. Current `MacExportPane` has no `ExportFlow`/stage — it is a
  single static config that writes a file and reveals it in Finder; there is no progress ring and no "Export complete" done card.
- Fix: lift the shared `ExportFlow` state machine (move it + `ProgressView`/`DoneView` into the shared layer so macOS can use them)
  and render `ProgressView(big)`/`DoneView(big)` in the rail when not in config, while keeping the real `ModelExporter` write.
- Files: `Sources/macOS/ContentView.swift`, `Sources/iOS/Studio/Screens/ExportScreen.swift`

### P1 · missing-mac — config rail drops Options and Destination
- Spec: rail = **"Format"** (6 rows) → **"Options"** (all 4, borderTop-except-first) → **"Destination"** (`DestRow`) → CTA → path.
  Current `config` (`:458-493`) has only Format rows then the CTA. No Options section, no Destination row.
- Fix: add the **"Options"** label + the 4 `EXPORT_OPTIONS` toggle rows (internal dividers only) and the **"Destination"** label +
  `DestRow` between Format and the CTA.
- Files: `Sources/macOS/ContentView.swift`

### P1 · missing-mac — toolbar diverges from the standard Mac toolbar
- Spec toolbar: bg `T.card2`, `borderBottom 0.5px line`, padding `0 18px 0 84px` (traffic-light inset), a **Back chip-button**
  (height 30, radius 8, `fieldFill`, `Ic back`, **"Model"**) → `viewer`, a vertical `Rule` (height 22), title
  **"Export · Celestial Bust"**, spacer, neutral chip **"6 formats"**. Current `:434-441`: `.padding(.horizontal, 20)`, no card2
  background, no 84pt left inset, no Back/"Model" button, no vertical Rule — only the title and the formats chip.
- Fix: rebuild the toolbar from the shared Mac toolbar recipe (`height 52`, `padding 0 18 0 84`, `T.card2`, bottom `StRule`), add the
  Back "Model" `StButton`/chip → `viewer`, the `StRule(vertical:)` height 22, then title + spacer + the `"\(count) formats"` chip.
- Files: `Sources/macOS/ContentView.swift`

### P1 · missing-mac/copy — CTA label is "Export usdz" and the output path line is missing
- Spec CTA: **"Export {format.name} · {format.size}"** = "Export USDZ · 184 MB", with a centered mono path under it:
  **"~/Exports/3DSeen/celestial-bust{format.ext}"** (`11px / text3 / marginTop 10`). Current `:489` is
  `StButton(title: "Export \(engineFormat.rawValue) …")` → renders **"Export usdz"** (lowercase enum raw value), and there is no
  path string.
- Fix: set the title to `"Export \(format.name) · \(format.size)"` using the selected `ExportFormatInfo`; add the centered mono
  `Text("~/Exports/3DSeen/celestial-bust\(format.ext)")` (`.mono(11)`, `theme.text3`, `.padding(.top, 10)`) below the button.
- Files: `Sources/macOS/ContentView.swift`

### P2 · missing-mac — preview is missing the bottom-center stats glass
- Spec preview: bottom-center `Glass radius=16` (padding `12px 18px`, gap 26) with 4 `Stat`s — `Format {name}` (color accentText),
  `Size {size.split(' ')[0]} unit="MB"`, `Triangles 4.2M`, `Textures "4K PBR"`. Current preview ZStack (`:444-450`) has only the
  top-left "AR Quick Look ready" accent chip; the stats glass is absent.
- Fix: overlay a bottom-center `StGlass(radius:16)` with the 4 `StStat(size:.sm)` values (use `format.size.split(" ").first` for Size).
- Files: `Sources/macOS/ContentView.swift`

### P2 · component — Mac re-implements a stripped FormatRow instead of the shared one
- Spec uses the same `FormatRow` (badge + ext + BEST chip + size + check well, ext `14px / 650`). Current Mac inlines a reduced row
  (`:464-481`): no BEST chip, **no right-hand check well** (so selection is only shown by bg/border), and ext at `.mono(13)` not 14.
- Fix: hoist the iOS `FormatRow` (and `DestRow`, `ProgressView`, `DoneView`) into the shared design layer — note `ExportScreen.swift`
  `import UIKit`s (for `ShareSheet`), so the shared rows must not depend on UIKit — then reuse them on macOS. This kills the
  duplicate row and restores BEST chip + check well + correct ext size.
- Files: `Sources/macOS/ContentView.swift`, `Sources/iOS/Studio/Screens/ExportScreen.swift`
</content>
</invoke>
