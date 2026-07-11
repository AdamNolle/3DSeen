# Viewer screen — fidelity & bug review

Scope: `Sources/iOS/Studio/Screens/ViewerScreen.swift` vs ground truth
`docs/design-ref/screens/viewer.jsx` (Phone + Pad variants) and `docs/design-spec/viewer.md`.
Mac variant is out of scope for the iOS port. Shared APIs (`StButton`, `StSegmented`,
`StStat`, `StGlass`, `StLabel`, `StRule`, `StIcon`, `liquidGlass`, `Stage`, `HeroModel`,
routes `.library`/`.export`, `SplatViewerScreen`) were verified to exist with the
signatures the screen uses.

Overall verdict: **minor-gaps**. No crashes, no broken navigation, no missing primary
region. Copy, tokens, and interactions are faithful. One concrete divergence on iPad plus
one positioning caveat.

---

## iPhone (`PhoneViewer`)

Faithful. Verified against the JSX:

- Stage + full-bleed `HeroModel(material: mat)`, scrim gradient stops
  (0.20 / 0.26 / 0.72 / 0.24) match `linear-gradient(180deg, …0.20, transparent 26%,
  transparent 72%, …0.24)`.
- Top bar: back glass 38×38 → `go(.library)` (icon `back` s18 ink), centered title pill
  `scan.name` = "Celestial Bust", export glass 38×38 → `go(.export)` (icon `export`). a11y
  labels present on both round buttons.
- Tool rail items `orbit/cube, measure/ruler, pin/pin, light/light`, icons-only — matches.
- Measure callout shows only when `tool == "measure"`, value `SampleData.measurements[0]` =
  "14.20 cm" (matches VERBATIM "14.20 cm"), positioned top 326 / leading 52 — matches.
- Bottom inspector header "Captured Today · Object · Full" + mono "v2"; stats row
  `Tris 4.2M · Tex 4K · PSNR 38.7 · Scale 14cm`; compact `MaterialPicker`. `StStat` has
  `frame(maxWidth:.infinity)` so the 4 stats split evenly = `repeat(4,1fr)`. Matches.
- Action row: AR (glass, flex 1) + Export (accent, flex 1.5) — width math uses 1/2.5 split
  = correct 40/60. Export → `go(.export)`.

Notes (not findings):
- The JSX `AR` button has no `onClick` (inert in the prototype). The Swift wires it to
  present `SplatViewerScreen` via `fullScreenCover($showSplat)`. This is an intentional,
  documented enhancement, visually identical (icon `scan` + "AR"); not a divergence.
- The prototype `StatusBar tone="light"` is intentionally omitted — native relies on the OS
  status bar. Correct for iOS; the top scrim keeps it legible.

---

## iPad (`PadViewer`)

Mostly faithful; the bespoke layout (left rail + right 326 inspector + bottom env bar) is
reproduced, not a phone reflow.

Verified: top bar (back 40×40 → library, title "Celestial Bust", meta chip
`FULL · 4.2M · 184 MB`, spacer, AirDrop glass·sm, Export accent·sm → export); left labeled
rail with 5 tools `orbit/measure/pin/light/ar`; two measure callouts at 358/350 ("14.20 cm")
and 700/305 ("21.8 cm") gated on `tool == "measure"`; right inspector geometry card
(Triangles 4.2M / Vertices 2.1M / Textures 4K PBR / PSNR 38.7 as a 1fr·1fr grid), material
card, measurements card "Measurements · 3 pins" iterating `SampleData.measurements` with the
M01 first-row no-top-border trick; bottom env bar `Segmented [Studio, Sunset, Soft, Field]`
bound to `env` (initial "Studio"), positioned bottom 18 / leading 110 / trailing 360.

### Finding 1 — iPad measurements card has extra "Add pin" / "CSV" buttons (P2, layout)

Ground truth — Pad measurements card (viewer.jsx lines 181-191) contains ONLY the section
`Label` + the `MEASUREMENTS` list. The "Add pin" / "CSV" button row exists **only in the Mac
variant** (lines 267-270). The spec confirms this: the iPad section (viewer.md line 72) lists
the card as "geometry stats, material override, and a measurements list" with no actions,
while Add-pin/CSV appear only under the Mac section (line 101).

Code — `PadViewer.measurementsCard` appends `measurementActions` (two no-op
`StButton`s "Add pin" + "CSV") after a `Spacer(minLength: 0)`:

```swift
Spacer(minLength: 0)
measurementActions.padding(.top, 12)   // Add pin / CSV — Mac-only in the reference
```

The card is `flex:1` in the design, so the reference shows the list at top over empty space;
the port fills that space with two controls the Pad design doesn't have. Note the card body is
an `[INFERRED]` slot in the source, so the reference itself is reconstructed — hence P2, not
P1 — but relative to the ground-truth file it is a clear, visible extra control row.

Fix — drop `measurementActions` (and the trailing `Spacer`) from the iPad
`measurementsCard`; keep Add-pin/CSV for the Mac inspector only.

### Finding 2 — measure callouts use absolute screen coordinates, not model-anchored (P2, layout)

Ground truth — the callouts are placed with the design-canvas absolute positions
(Phone 402×874: 52/326; Pad 1194×834: 358/350 and 700/305) intended to land on the bust's
chin/crown/shoulder.

Code — `measureCallout` / `measureCallouts` apply those raw point offsets with
`.ignoresSafeArea()`, so they are screen-absolute. The `HeroModel` is rendered full-bleed and
centered/scaled by `Stage`, so on any device whose bounds differ from the design canvas
(12.9" iPad, portrait orientation, larger iPhones, Split View) the pills drift off the model
features. Same limitation exists in the prototype, but real iOS devices vary in size where the
single JSX canvas does not.

Fix — anchor the callouts to normalized stage-space fractions (e.g. position as a fraction of
the `Stage`'s `GeometryReader` size) rather than absolute points, or gate them to the known
reference size. Low priority — only visible on non-reference sizes.

---

## Logic / runtime / a11y

- No force-unwraps in the screen. `SampleData.measurements[0]` is safe (3 rows, non-empty);
  `SampleData.scans[0]` safe.
- `@State` (`mat`, `tool`, `showSplat` / `env`) and bindings (`ToolRail active:$tool`,
  `MaterialPicker value:$mat`, `StSegmented value:$env`) are all correct.
- `ForEach` ids are unique (`measurements` by `.id` M01/M02/M03; rail by `.id`;
  `STUDIO_MATERIALS` Identifiable). No collisions.
- Navigation targets correct: back → `.library`, export buttons → `.export` (both routes
  exist on `StudioModel.go`). AR → `SplatViewerScreen` (exists, `onClose` wired).
- a11y: round chrome buttons, rail buttons, material swatches, and the measure pill all carry
  `accessibilityLabel`; selected rail/material add `.isSelected`. Good coverage.
