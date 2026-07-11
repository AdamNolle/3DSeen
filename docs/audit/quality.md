# Quality / Detail-Tier Picker — fidelity audit

Spec: `docs/design-spec/quality.md` · Ground truth: `docs/design-ref/screens/quality.jsx`
Swift: `Sources/iOS/Studio/Screens/QualityScreen.swift`
Router: `Sources/iOS/Studio/StudioRouter.swift`

**Verdict.** The iPhone (`PhoneQuality`) port is faithful and fully functional — selection state, scale slider, selected card, two collapsed alternate rows, and the sticky CTA all match the JSX. The big gap is the **iPad**: there is *no* `PadQuality` layout at all. `StudioRouter` renders the iPhone `QualityScreen` on every size class and merely width-caps it via `readableContentWidth(720)`, so iPad users get a centered phone column instead of the spec's two-region dashboard (hero + FidelityChart + 5-up tier grid + info card). The named shared components `FidelityChart` and `StepTabs` do not exist anywhere in the codebase. This screen has **no Mac variant** (`quality.md` header: "no Mac variant"; Mac flow omits `quality`), so no macOS work is required. Phone defects are all P2 polish. Note: the `BEST`/`SELECTED` badge copy in the Swift matches the JSX ground truth (the `quality.md` prose that says "Recommended"/"Selected" is the doc that drifted) — no copy fix needed there.

---

## iPad — bespoke layout (missing)

### P1 · missing-ipad · `PadQuality` dashboard absent; iPad gets the phone column
`StudioRouter.swift:68` maps `.quality` → `QualityScreen()` for all size classes; `QualityScreen` ends its scroll content with `.readableContentWidth()` (`QualityScreen.swift:102`), which on regular width just centers the iPhone column at maxWidth 720. The spec's entire iPad screen is missing.

Spec (`quality.md` §PadQuality / `quality.jsx:134-175`): absolute fill, `<PadStatusBar/>`, content `top 30 padding 24` flex-column **no scroll**, containing:
1. Header row: left group = back `38×38` radius999 `fieldFill` (`Ic back s17 c text2` → `go('briefing')`) + text block `<Label>New Scan · Step 3 of 4</Label>` over `"Choose detail tier"` (**17 / 700**, ls −0.3, ink, marginTop 2); center `<StepTabs active={2}/>`; right `<Button kind="accent" size="sm">` `Ic bolt` + `"Capture at {tier.name}"` → `go('viewfinder')`.
2. Two-column grid `1fr 1fr` gap 16 marginTop 18: **Left Card** radius22 pad22 — `<Label>Apple PhotogrammetrySession</Label>`, headline `"Five tiers,\nsame source frames."` (**32 / 720**, ls −1.1, lineHeight 1.02), body `"3DSeen captures once at Raw and re-derives every lower tier on demand. You'll never need to re-scan."` (14 text2 lh1.45), stats row gap28 over `[['Captured frames','340',ink],['Raw archive','1.1 GB',ink],['Re-process','Unlimited',good]]` (value **22 / 720**, ls −0.5). **Right Card** radius22 pad22 — `<Label color={accentText}>Fidelity comparison</Label>` + `<FidelityChart sel={sel}/>`.
3. 5-up tier grid `repeat(5,1fr)` gap12 `flex 1` marginTop 16: all five `<TierCard compact selected={t.id===sel} onPick={setSel}/>`.
4. Info Card radius14 pad`10 16` marginTop16 (row, gap10): `Ic info s16 c accent` + 12.5/text2 sentence `"For commercial fidelity, capture at `**Raw**` and view/share at `**Full**`. Re-derive in the library anytime — your iPhone keeps the archive, your Mac does the heavy lifting."` (the words **Raw** and **Full** bold in `ink`).

**Fix.** Add a `PadQuality` view and branch in the router (or inside `QualityScreen`) on `@Environment(\.horizontalSizeClass)`: render `PadQuality` when `.regular`. Build the fixed (non-scrolling) column with `LazyVGrid`/`Grid` for the 1fr·1fr top row and a 5-column `HStack`/`Grid` for the tier row (`.frame(maxWidth:.infinity)` cells, fixed height via `flex 1` → equal-height row). The existing `TierCard(compact: true)` already implements the compact 5-up card and can be reused as-is. Use `StCard(radius: 22)` for hero/chart cards, `StCard(radius: 14)` for the info card, `StStat`/`.sf(22,.bold)` for the hero stats (Re-process in `theme.good`). Keep all copy verbatim, including the bold `Raw`/`Full` runs (use `Text("…") + Text("Raw").bold().foregroundColor(theme.ink) + …` or `AttributedString`).

### P1 · component · `FidelityChart` not implemented
The named shared PSNR chart used by the iPad right card does not exist anywhere (`grep` for `FidelityChart` → none). Spec (`quality.md` §FidelityChart / `quality.jsx:112-132`): SVG `viewBox 0 0 w h` (`w 480 h 170`): X-axis `x1=30 y1=h−28 x2=w−10` stroke `axis`; four dashed gridlines `y=20+i*(h−70)/3` stroke `grid` dash `2 4`; per tier `x=55+i*((w−80)/4)`, `y=(h−28)−((psnr−18)/28)*(h−56)`; connecting polyline segments stroke `accentLine` width 1.5; point `circle r={on?7:4.5} fill={on?accent:card} stroke=accent sw1.6`; tier label `name.toUpperCase()` at `y=h−12` fontSize9 mono `text3` anchor middle; value `psnr` at `y=y−11` fontSize11 `ink` weight700 mono anchor middle; Y caption `"PSNR dB"` at `x34 y16` fontSize9 mono `text3`.

**Fix.** Implement `FidelityChart(sel:)` as a `Canvas` (or `Path`+overlay `Text`) using the exact `x`/`y` formulas above, recomputing the active point radius from `sel`. Use `theme.axis/grid/accentLine/accent/card/ink/text3`, `.font(.mono(9))` / `.mono(11)` with `.monospacedDigit()` for the value labels. `preserveAspectRatio="none"` → let it stretch to the card's width.

### P1 · component · `StepTabs` primitive missing
The iPad header calls `<StepTabs active={2}/>` (`quality.jsx:146`). No `StepTabs` exists in `Sources/` (also referenced by other pad wizard screens). Without it the iPad header center region can't be built.

**Fix.** Add a shared `StepTabs(active: Int, total: Int = 4)` chrome component (likely in `StudioChrome.swift`) — a centered row of segment/pill indicators with the active index emphasized (accent) — then place it in the `PadQuality` header.

---

## iPhone — polish (P2)

### P2 · component/token · "BEST"/"SELECTED" tier badges render at 12px, spec is 9px
`quality.jsx:42-43` renders `<Chip tone="accent" style={{ fontSize: 9 }}>BEST</Chip>` (and `SELECTED`). `QualityScreen.swift:160` uses `StTextChip(text: "BEST", tone: .accent)`, but `StChip` hardcodes `.font(.sf(12, .semibold))` (`Primitives.swift:252`) with no size override, so the badge is ~33% too large.
**Fix.** Add `var fontSize: CGFloat = 12` to `StChip`/`StTextChip` and pass `9` for the tier badges (or inline a small accent capsule in `TierCard` with `.font(.sf(9,.semibold))`).

### P2 · interaction · active scale-dot halo is inset instead of an outward glow
`quality.jsx:87` gives the selected dot `boxShadow: '0 0 0 3px accentSoft'` — a 3px halo *outside* the 13px dot. `QualityScreen.swift:66` draws it as `.overlay(Circle().strokeBorder(theme.accentSoft, lineWidth: on ? 3 : 0))`, which insets the ring *into* the dot, shrinking the visible fill.
**Fix.** Render the halo behind the dot: `.background(Circle().fill(theme.accentSoft).frame(width: 19, height: 19))` when `on` (13 + 2·3), or `.overlay(Circle().stroke(theme.accentSoft, lineWidth: 3).padding(-3))`.

### P2 · token · unselected scale label weight 500 mapped to `.regular`
`quality.jsx:88`: `fontWeight: on ? 700 : 500`. `QualityScreen.swift:68` uses `.mono(9.5, on ? .bold : .regular)` — 500 should be `.medium`, not `.regular` (400).
**Fix.** `.font(.mono(9.5, on ? .bold : .medium))`.

### P2 · token · weight 720 mapped inconsistently (`.heavy` vs `.bold`)
The 28px title "How much detail?" uses `.font(.sf(28, .heavy))` (`QualityScreen.swift:42`) while `TierCard` names — also weight 720 in the JSX — use `.font(.sf(…, .bold))` (`QualityScreen.swift:159`). Same source weight, two different SwiftUI weights (`.heavy`≈800 vs `.bold`=700).
**Fix.** Standardize all 720 occurrences on one weight (`.bold` is closest to the 700–720 design intent) so the title and card headings read consistently; apply the same choice to the future iPad 32/720 headline.

### P2 · perf/layout · TierPreview wireframe stroke not scaled to size
`quality.jsx:19` strokes the lat-line ellipses with `strokeWidth="0.5"` in the 100-unit viewBox, so the line weight scales with `size` (≈0.42px at 84, ≈0.20px at 40). `QualityScreen.swift:132` uses a fixed `lineWidth: 0.5` (points), so the 40px inline previews show lines ~2.5× heavier than the 84px card previews.
**Fix.** Multiply by the existing `scale`: `lineWidth: 0.5 * scale` in the `ctx.stroke(...)` call.

### P2 · component/token · `TierCard` hand-rolls card chrome instead of `StCard`; shadow under-blurs
`TierCard` builds its own `background`/`overlay`/`shadow` (`QualityScreen.swift:182-184`) with `.shadow(color: .black.opacity(0.06), radius: 10, y: 6)`. The token `cardShadow` is two layers (`0 1px 2px …, 0 10px 30px …`); a 30px CSS blur ≈ SwiftUI `radius 15`, and the tight 1px layer is dropped, so the card sits flatter than peers built with `StCard`.
**Fix.** Either reuse `StCard` (extend it to accept a `selected` accent ring + `accentSoft` fill) or factor the `cardShadow` two-layer recipe into a shared modifier and apply it here.

### P2 · token/a11y · phone top-right close icon size 17 vs spec 16
`quality.jsx:71`: `Ic name="close" s={16}`. The shared `CircleIconButton` hardcodes `StIcon(... size: 17)` (`StudioChrome.swift:14`) for every icon, so close renders at 17 (back at 17 is correct).
**Fix.** Low priority — give `CircleIconButton` an `iconSize` param (default 17) and pass 16 for the close button, or accept the 1px delta.

### P2 · layout · scroll insets drift
`quality.jsx:67` scroll padding is `'8px 20px 110px'` (top 8 / bottom 110). `QualityScreen.swift:101` uses `.padding(.bottom, 120)` and no top inset (top 8 omitted). Trivial spacing drift under the sticky CTA.
**Fix.** Use `.padding(.top, 8)` and `.padding(.bottom, 110)` to match.
