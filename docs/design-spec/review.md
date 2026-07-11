# Post-Capture Review — SwiftUI implementation spec

Source: `docs/design-ref/screens/review.jsx`
Exports (no Mac variant): `PhoneReview`, `PadReview`.
File intent (header comment): *"post-capture review: coverage map, weak spots, retake (iPhone · iPad)"*.

Light-theme screen (`background T.bg`). Shows the coverage dome, the flagged weak spots (from shared `DROPS`), capture stats, and lets the user **retake** weak areas or proceed to **compute**. Phone = single scroll column; iPad = two-column dashboard (coverage hero + weak-spots/frame-timeline column).

---

## Data

### REVIEW_STATS (exact)
```
[ { k:'Frames',    v:'340' },
  { k:'Coverage',  v:'92%',  c: () => T.good },
  { k:'Sharpness', v:'0.93' },
  { k:'Parallax',  v:'8.4°' },
  { k:'Rejected',  v:'6',    c: () => T.warn } ]
```
Rendered via `<Stat k v c size="sm" />` (iPad hero footer). `c` callbacks color the value (Coverage = good/green, Rejected = warn/amber).

### sevColor(s)
`s === 'high' → T.bad`; `s === 'med' → T.warn`; else `T.accent`. Used to tint each weak-spot row from `DROPS[i].severity`.

### DROPS
Shared const (already extracted); each entry feeds a weak-spot row (severity → `sevColor`, plus label + hint text). The coverage dome also consumes `drops={DROPS}` to place the colored shells/markers.

---

## PhoneReview (iPhone)

Root: absolute fill `background T.bg`. `<StatusBar />`. Scroll body (`top 54`, `overflow auto`, `padding "8px 20px 110px"`).

1. **Header row** (flex, align center, space-between):
   - Back button: `36×36` radius999 `T.fieldFill`, `Ic name="back" s=17 c=T.text2`.
   - `<Chip tone="good"><span 6×6 radius99 background T.good /> Capture complete</Chip>` (green dot + "Capture complete").
   - Share button: `36×36` radius999 `T.fieldFill`, `Ic name="share" s=16 c=T.text2`.
2. **Title block** (marginTop 18):
   - `<Label color={T.good}>Coverage 92% · 340 frames</Label>`.
   - `"Review & retake"` — **28 / 720**, ls −0.9, `T.ink`, marginTop 6.
   - Subtitle `"3 weak spots flagged. Retake them, or proceed to compute."` — 13.5, `T.text2`, marginTop 8.
3. **Coverage Card** `radius 22 padding 16 marginTop 14` (flex column, align center):
   - Legend row: `[['Strong',T.good], ['Weak',T.warn], ['Missing',T.bad]].map` → each `dot 8×8 radius99 background=c` + `<Label>{l}</Label>` (gap 6).
   - `<CoverageDome size={258} drops={DROPS} />`.
4. **Weak-spots Card** `radius 20 padding "4px 16px" marginTop 12`: `DROPS.map((d,i) => …)` wrapped in `React.Fragment`:
   - `const c = sevColor(d.severity)`.
   - A row: numbered **badge** `{i+1}` (small, severity-tinted background `${c}1f`, `st-num`, color `c`), the drop **label** (≈13.5 / 650, `T.ink`), a **hint** line (`st-num` ≈11, `T.text3`), and a **Retake** button (pill, `onClick → go('viewfinder')`).
   - `{i < DROPS.length - 1 && <Rule />}` divider between rows.
5. **Sticky footer** (absolute bottom 28, left/right 20; flex, gap 8):
   - `<Button kind="secondary" onClick={() => go('viewfinder')}>` — "Retake all" (refresh icon).
   - `<Button kind="accent" style={{ flex: 1.5 }} onClick={() => go('compute')}>` → `Ic name="chip" s=16 c=T.onAccent` + ` Compute now`.

---

## PadReview (iPad)

Root: absolute fill `background T.bg`. `<PadStatusBar />`. Container absolute inset 0, `top 30`, flex column, `padding 24` (fixed; the grid flexes to fill — **no page scroll**).

1. **Header row** (flex, align center, space-between):
   - Left group (flex, align center, gap 12): back button `38×38` radius999 `T.fieldFill` `Ic back s=17 c=T.text2` `onClick → go('viewfinder')`; text block `<Label color={T.good}>Post-capture · Object</Label>` over `"Review & retake"` (**17 / 700**, ls −0.3, `T.ink`, marginTop 2).
   - Right group (flex, gap 8):
     - `<Button kind="secondary" size="sm" onClick={() => go('viewfinder')}>` → `Ic name="refresh" s=15 c=T.ink` + ` Retake all`.
     - `<Button kind="accent" size="sm" onClick={() => go('compute')}>` → `Ic name="chip" s=16 c=T.onAccent` + ` Compute now`.
2. **Two-column grid** (`flex 1`, `gridTemplateColumns "1.1fr .9fr"`, gap 16, `minHeight 0`, marginTop 18):

   ### Left — coverage hero `Card radius 24 padding 24` (flex column, minHeight 0)
   - Header row (space-between, align flex-start):
     - Left text: `<Label color={T.good}>Coverage map · 92%</Label>`; `"You almost have it."` (**34 / 720**, ls −1.1, marginTop 6, lineHeight 1.02); body `"Three weak spots — color-coded shells show density and angle confidence around the object."` (14, `T.text2`, marginTop 6, lineHeight 1.4, maxWidth 360).
     - Right legend column (gap 8): `[['Strong',T.good], ['Weak',T.warn], ['Missing',T.bad]]` → `dot 9×9 radius99 background=c` + `<Label>{l}</Label>` (gap 7).
   - Center (flex 1, centered, minHeight 0): `<CoverageDome size={400} drops={DROPS} />`.
   - Footer stats (grid `repeat(5,1fr)`, gap 12, paddingTop 14, `borderTop 0.5px solid T.line`): `REVIEW_STATS.map(s => <Stat k={s.k} v={s.v} c={s.c ? s.c() : undefined} size="sm" />)` → Frames 340 · Coverage 92% (green) · Sharpness 0.93 · Parallax 8.4° · Rejected 6 (amber).

   ### Right column — weak spots + frame timeline (stacked)
   - **Weak-spots Card**: `DROPS.map` list of weak spots, each row severity-tinted (`sevColor`), with the drop label/hint and per-row **Skip / Retake** actions (Retake → `go('viewfinder')`), `<Rule />` between rows.
   - **Frame-timeline Card**: a horizontal filmstrip of **72** frame slots (`calc(8.333% …)` cell widths), with **rejected** frames marked at indices `{14, 32, 33, 51, 60}` (rendered with the warm/rejected gradient stop pair `['#D8C3A4','#5E4B30']`). Footer stats: **Kept 334 · Rejected 6 · Interval 0.18s**.

---

## Interactions / navigation
- Back: Phone share-row back button; iPad header back → `go('viewfinder')`.
- **Retake** (per weak-spot row, and the "Retake all" button) → `go('viewfinder')` (return to live capture to re-shoot).
- **Compute now** (accent CTA, both devices) → `go('compute')` (proceed to reconstruction).
- Selecting/skipping individual weak spots is local to the list (iPad has Skip + Retake per row).

## Device differences
- **Phone**: vertical scroll — capture-complete chip header, title/subtitle, one coverage Card (legend + 258px dome), a weak-spots Card (numbered rows + Rule dividers + per-row Retake), sticky footer with Retake all / Compute now (the accent button is `flex 1.5`, i.e. wider).
- **iPad**: fixed dashboard. Header carries the two CTAs inline (size sm). A 1.1fr/0.9fr two-column grid: a large coverage **hero** (400px dome + 5-up REVIEW_STATS strip + side legend) on the left; the weak-spots list and the 72-frame **filmstrip timeline** (Kept/Rejected/Interval) on the right.

## Dynamic
- `CoverageDome(drops)` renders the colored coverage shells (strong/weak/missing) around the object; weak spots correspond to `DROPS`. Phone 258 / iPad 400.
- Weak-spot rows are tinted live by `sevColor(severity)` (badge bg = `${c}1f` = color at ~12% alpha).
- Frame timeline highlights rejected frames; stats are computed (Kept 334 = 340−6).

## Implementation notes for SwiftUI
- **CoverageDome** is the centerpiece and the trickiest element: a 3D-ish dome/hemisphere whose surface cells are colored by coverage density and angle confidence (Strong `T.good` / Weak `T.warn` / Missing `T.bad`), placing markers from `DROPS`. It must scale cleanly from 258 (phone) to 400 (iPad). Keep the exact legend wording (Strong/Weak/Missing) and the green "Coverage … 92%" labels.
- **Severity tinting**: implement `sevColor` and the `${c}1f` (≈ `.opacity(12/255)` → use `color.opacity(0.12)`) badge fill so weak-spot rows read at a glance.
- **Frame timeline**: a 72-cell `HStack` (each ~8.333% width) with rejected indices `{14,32,33,51,60}` drawn in the `#D8C3A4→#5E4B30` gradient; footer Kept/Rejected/Interval as `Stat`-style mono numerics.
- **REVIEW_STATS** uses the shared `Stat` component at `size="sm"`; wire the `c()` callbacks so Coverage is green and Rejected is amber. Render as a 5-column equal grid with a 0.5px top hairline.
- Preserve every literal: chip "Capture complete", titles "Review & retake" / "You almost have it.", subtitles, "Coverage 92% · 340 frames" / "Coverage map · 92%" / "Post-capture · Object", button labels "Retake all" / "Compute now", and stat keys/values. (Note `&amp;` in source = literal `&` in "Review & retake".)
- Buttons: `secondary` (Retake) vs `accent` (Compute, `onAccent` icon tint). Phone footer accent button is wider (`flex 1.5`).
