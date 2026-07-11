# Audit — Review screen (`review`)

Spec: `docs/design-spec/review.md` · Ground truth: `docs/design-ref/screens/review.jsx`
Current Swift: `Sources/iOS/Studio/Screens/ReviewScreen.swift`
Render helpers: `Sources/Shared/Studio/StudioRender.swift` (`CoverageDome`, `FrameStrip`)
Data: `Sources/Shared/Studio/SampleData.swift`
Router: `Sources/iOS/Studio/StudioRouter.swift`

No Mac variant exists for this screen (spec header: "no Mac variant"; FLOWS mac omits `review`). Mac is intentionally out of scope.

---

## iPhone (`PhoneReview`)

The phone port is largely faithful. Header (back / "Capture complete" chip / share), title block, coverage card, numbered weak-spot rows with per-row Retake, and the Retake-all / Compute-now footer are all present and route correctly (`go('viewfinder')` / `go('compute')`). Remaining gaps are polish-level.

### P2 — layout — Footer accent CTA not wider (`flex 1.5`)
Spec footer: `<Button kind="secondary" style={{flex:1}}>Retake all</Button>` + `<Button kind="accent" style={{flex:1.5}}>Compute now</Button>` — the accent button is **1.5× wider**. Current `ReviewScreen.swift:81-85` gives both `full: true` inside a plain `HStack(spacing: 8)`, so they render at equal width.
Fix: drop `full:true` and split the width 2:3, e.g. wrap each in `.containerRelativeFrame(.horizontal, count: 5, spacing: 8) { w, _ in w * span }` (secondary span 2, accent span 3), or use `GeometryReader` to size them `1 : 1.5`.

### P2 — layout — Coverage dome smaller than spec
Spec: `<CoverageDome size={258} drops={DROPS} />` (phone). Current `ReviewScreen.swift:44` `CoverageDome(drops: SampleData.dropouts).frame(height: 240)` — 240, and only constrains height (width fills the card).
Fix: `.frame(width: 258, height: 258)` (or at minimum `.frame(height: 258)`).

### P2 — token — Weak-spot badge number and hint should be mono (`st-num`)
Spec badge: `<span className="st-num" style={{fontSize:11, fontWeight:700}}>` and hint: `<div className="st-num" style={{fontSize:11}}>` — `st-num` = tabular monospace. Current `ReviewScreen.swift:56,59` uses `.font(.sf(11, .bold))` for the badge digit and `.font(.sf(11))` for the hint — proportional SF, not mono.
Fix: use `.font(.mono(11, .bold))` for the badge number and `.font(.mono(11))` (or `.sf(11).monospacedDigit()`) for the hint to match the numeric/mono treatment.

### P2 — token — Title weight `.heavy` vs spec `720`
Spec: `"Review & retake"` `fontWeight: 720`. Current `ReviewScreen.swift:30` `.font(.sf(28, .heavy))` (~800). Consistent with the app's heavy-display mapping but heavier than 720.
Fix: optional — introduce a 720-equivalent weight or accept the app convention.

### P2 — token — Weak-spots card vertical padding missing (`4px 16px`)
Spec: `<Card radius={20} style={{ padding: '4px 16px' }}>`. Current `ReviewScreen.swift:50` `StCard(radius: 20, pad: 0)` with inner `.padding(.horizontal, 16)` only — the 4px top/bottom inset is dropped.
Fix: add `.padding(.vertical, 4)` to the inner `VStack`.

### P2 — wiring/a11y — Share button is a no-op
`ReviewScreen.swift:25` `CircleIconButton(icon: "share") {}` — empty action. The spec's share button likewise has no handler, so this is faithful, but it is a dead control; also `CircleIconButton` hardcodes icon size 17 whereas spec share icon is `s={16}` (back is 17 and matches).
Fix (optional): wire to a `ShareLink`/share sheet, and add a VoiceOver label (already inferred as "Share" by `CircleIconButton.label`).

---

## iPad (`PadReview`)

### P1 — missing-ipad — Entire bespoke iPad dashboard is absent
`StudioRouter.swift:69` dispatches `.review` → `ReviewScreen()` for **all** size classes; there is no `PadReview`. On iPad the iPhone screen merely reflows (capped at 720 via `.readableContentWidth()`), leaving the whole right side of the canvas empty. The spec's iPad is a fixed, non-scrolling two-column dashboard that shares almost nothing structurally with the phone column. Missing pieces:

1. **Header row** (`review.jsx:75-84`): `PadStatusBar`, back button `38×38` `fieldFill` → `go('viewfinder')`, a text block `<Label color={T.good}>Post-capture · Object</Label>` over `"Review & retake"` (**17 / 700**, ls −0.3, `ink`, marginTop 2), and **inline CTAs on the right** — `Button kind="secondary" size="sm"` "Retake all" (refresh icon, `c=T.ink`) + `Button kind="accent" size="sm"` "Compute now" (chip icon, `c=T.onAccent`). The phone screen has neither this header layout nor inline CTAs.
2. **Two-column grid** (`review.jsx:85`): `display:grid; gridTemplateColumns:'1.1fr .9fr'; gap:16; minHeight:0; marginTop:18`, `flex:1` (fills, no page scroll). Absent entirely.
3. **Left — coverage hero** `Card radius={24} padding={24}` (`review.jsx:87-109`):
   - Header: `<Label color={T.good}>Coverage map · 92%</Label>`, title `"You almost have it."` (**34 / 720**, ls −1.1, lineHeight 1.02), body `"Three weak spots — color-coded shells show density and angle confidence around the object."` (14, `text2`, lineHeight 1.4, maxWidth 360), and a **right-aligned legend column** (Strong/Weak/Missing, 9×9 dots, gap 8/7).
   - Center: `<CoverageDome size={400} drops={DROPS} />`, vertically centered, `flex:1`.
   - Footer: 5-up `gridTemplateColumns:'repeat(5,1fr)'`, `paddingTop:14`, `borderTop:0.5px solid T.line`, rendering `REVIEW_STATS.map(s => <Stat … size="sm" />)` → Frames 340 · Coverage 92% (green) · Sharpness 0.93 · Parallax 8.4° · Rejected 6 (amber).
4. **Right column — stacked cards** (`review.jsx:111-162`):
   - **Weak-spots card** `Card radius={20} padding={18}`: `<Label color={T.warn}>Weak spots — 3 flagged</Label>`, then `DROPS.map` rows with a `30×30` severity-tinted badge (`${c}1f`, st-num 13/700), label (14/650 ink) + hint (st-num 11.5 text3), and **per-row `Button kind="ghost" size="sm"` "Skip" + `Button kind="secondary" size="sm"` "Retake"** (Retake → `go('viewfinder')`); `0.5px line` borderTop between rows (not the phone's numbered `St`-style Retake pill).
   - **Frame-timeline card** `Card radius={20} padding={18} flex:1`: header `<Label color={T.accentText}>Frame timeline · 340</Label>` + `<Segmented size="sm" options={['All','Keep','Reject']} value="All" />`; a **flex-wrap grid of 72 cells** (`width:'calc(8.333% - 4px)'`, aspectRatio 1, radius 5) with rejected indices `{14,32,33,51,60}` drawn as `badSoft` fill + `0.5px solid T.bad` border + `×` glyph, non-rejected cells a warm radial gradient cycling 3 tone pairs (`#EFE7D7/#9B8769`, `#D8C3A4/#7A6244`, `#CBB592/#5E4B30`); footer (marginTop auto, `borderTop 0.5px line`) three `Stat size="sm"`: **Kept 334** (good) · **Rejected 6** (warn) · **Interval 0.18s**.

Fix: Add a `PadReview`-style view and branch in `StudioRouter.swift` (`@Environment(\.horizontalSizeClass)` → `regular` renders the dashboard, `compact` renders `ReviewScreen`), or split `ReviewScreen` into `body` with a size-class switch. Reuse `StCard`, `StButton` (`.secondary`/`.accent`/`.ghost`, `size:.sm`), `StLabel`, `StStat(size:.sm)`, `StSegmented`, `CoverageDome`. Implement the 5-up stats strip with a `LazyVGrid`/`HStack` of `StStat` + a top `StRule`. See data/component findings below for prerequisites.

### P1 — wiring — `REVIEW_STATS` data constant missing
The iPad hero footer renders `REVIEW_STATS` (`review.jsx:3-9`): `Frames 340`, `Coverage 92%` (c: `T.good`), `Sharpness 0.93`, `Parallax 8.4°`, `Rejected 6` (c: `T.warn`). No equivalent exists in `SampleData.swift` (only `scans`, `exportFormats`, `measurements`, `dropouts`). The iPad layout cannot be built without it.
Fix: add `static let reviewStats: [ReviewStat]` to `SampleData` with a per-row optional color callback (Coverage → `theme.good`, Rejected → `theme.warn`), e.g. a struct `{ k, v, color: KeyPath<St,Color>? }` resolved at render via the environment theme.

### P1 — component — No wrapping 72-cell frame-timeline primitive
The existing `FrameStrip` (`StudioRender.swift:304`) is a single non-wrapping `HStack` with rejected indices **computed** (≈`count*0.34`, `count*0.72`); the iPad timeline needs a **wrapping** 72-cell grid (`8.333%` ≈ 12 per row) with **explicit** rejected indices `{14,32,33,51,60}`, the warm 3-pair gradient cycle, and the `×` marker. It also pairs with a `Segmented` All/Keep/Reject filter that should filter/highlight the strip.
Fix: extend `FrameStrip` (or add a `ReviewFrameStrip`) backed by a `LazyVGrid`/wrapping layout taking `count`, an explicit `rejected: Set<Int>`, and the tone-pair list; wire the `StSegmented` selection to filter Keep/Reject.

---

## Summary
Phone is a faithful port with only P2 polish gaps (accent CTA width, dome 240→258, mono on badge/hint numerics, minor paddings/weights). The dominant gap is the **completely missing iPad bespoke dashboard** — the router sends iPad straight to the iPhone column, so the coverage hero (400 dome + 5-up REVIEW_STATS strip + side legend + "You almost have it."), the inline header CTAs, the Skip/Retake weak-spots card, and the 72-cell frame-timeline (with Segmented filter and Kept/Rejected/Interval stats) are all absent. Building it also requires adding the `REVIEW_STATS` data and a wrapping frame-timeline component. No Mac variant is expected.
