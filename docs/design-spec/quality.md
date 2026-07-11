# Quality / Detail Tier Picker — SwiftUI implementation spec

Source: `docs/design-ref/screens/quality.jsx`
Exports (no Mac variant): `PhoneQuality`, `PadQuality`, and the `TIERS` data array.
File intent (header comment): *"detail / quality tier picker (5 tiers)"*. Step 3 of 4 in the New-Scan flow. Mirrors Apple's `PhotogrammetrySession` quality tiers.

This is a **light-theme** screen (`background T.bg`). Phone = vertical scroll list; iPad = fixed two-region dashboard (hero + chart + 5-up tier grid).

---

## Data — `TIERS` (exact, order top→bottom)

| id | name | tag | tris | tex | size | time | use | psnr | flag |
|----|------|-----|------|-----|------|------|-----|------|------|
| preview | Preview | Real-time draft | 120k | 512 | 12 MB | 8 s | Snap a quick reference | 22 | |
| reduced | Reduced | Mobile-ready | 480k | 1024 | 38 MB | 40 s | AR Quick Look, web preview | 28 | |
| medium | Medium | Most projects | 1.2M | 2048 | 92 MB | 2:15 | Catalogs, light VFX, social | 33 | **recommended: true** |
| full | Full | Studio fidelity | 4.2M | 4096 | 184 MB | 6:42 | Commercial, museum, PBR-correct | 38 | |
| raw | Raw | Photogrammetric archive | 16M+ | 8192 | 1.1 GB | 21 min | Re-process later · color-managed EXR | 44 | |

Default selection on both devices: `useState('medium')`.

---

## Shared components

### TierPreview(tier, size = 84)
- `segs` density = `{preview:6, reduced:10, medium:14, full:20, raw:28}[tier.id] || 12`.
- Container: `size×size`, `borderRadius 14`, `overflow hidden`, `position relative`, `flexShrink 0`, inset hairline `boxShadow: inset 0 0 0 0.5px T.line`.
- Contents: a stylized **mesh-density thumbnail** whose triangle/segment count scales with `segs` (higher tier = visibly denser wireframe/shaded preview). *(Exact inner SVG not transcribed verbatim — render a density preview keyed off `segs`.)*

### TierCard(tier, selected, compact = false, onPick)
Tap target (`button`, `className="st-tap"`, `onClick → onPick(tier.id)`), full width, `textAlign left`:
- `borderRadius`: compact **18**, else **20**. `padding`: compact **14**, else **18**.
- `background`: `selected ? T.accentSoft : T.card`.
- `border`: `0.5px solid ${selected ? T.accentLine : T.line}`.
- `boxShadow`: `selected ? "0 0 0 1px {T.accentLine}, {T.cardShadow}" : T.cardShadow`.
- `display flex; flexDirection column; height: compact ? 100% : auto`.
- **Top row** (flex, align flex-start, gap 14):
  - `<TierPreview tier={tier} />` (size 84 default; the small inline list passes 40).
  - Info column (`flex 1, minWidth 0`):
    - Name row (flex, align center, gap 6, wrap): name `fontSize: compact?17:20`, **weight 720**, ls −0.4, color `T.ink`.
      - if `tier.recommended` → a small **"Recommended"** chip (accent).
      - else if `selected` → a **"Selected"** chip.
    - `<Label color={selected ? T.accentText : T.text3}>{tier.tag}</Label>` (marginTop 3).
    - if `!compact`: use-text `fontSize 13`, `color T.text2`, marginTop 6, lineHeight 1.35 → `{tier.use}`.
- **Stats row** (flex, marginTop 14, paddingTop 12, `borderTop 0.5px solid T.line`): four equal cells `[['Triangles',tris], ['Textures', tex+'px'], ['Size', size], ['Compute', time]]`; each `flex 1`, `paddingLeft: i?10:0`, `borderLeft: i ? 0.5px solid T.line : none`; `<Label>{k}</Label>` over value (`st-num`, `fontSize: compact?13:15`, **700**, ls −0.2, `T.ink`, marginTop 3).

### FidelityChart(w = 480, h = 170, sel)  — used by iPad only
SVG (`viewBox 0 0 w h`, `preserveAspectRatio none`):
- X axis line `x1=30 y1=h−28 x2=w−10 y2=h−28 stroke=T.axis`.
- 4 dashed grid lines: `i∈0..3`, `y=20+i*(h−70)/3`, `stroke=T.grid strokeDasharray="2 4"`.
- For each tier `i`: `x=55+i*((w−80)/4)`, `y=(h−28)−((psnr−18)/28)*(h−56)`, `on = id===sel`. Inside `<g>`:
  - connecting segment to next tier (`i<4`): `line … stroke=T.accentLine strokeWidth=1.5` (forms the PSNR curve).
  - point `circle r={on?7:4.5} fill={on?T.accent:T.card} stroke=T.accent strokeWidth=1.6`.
  - tier label `text {name.toUpperCase()}` at `y=h−12`, `fontSize 9`, `fill T.text3`, mono, anchor middle.
  - value `text {psnr}` at `y=y−11`, `fontSize 11`, `fill T.ink`, **700**, anchor middle, `st-num`.
- Y-axis caption `text "PSNR dB"` at `x34 y16`, `fontSize 9`, `fill T.text3`, mono.

---

## PhoneQuality (iPhone)

Root: absolute fill, `background T.bg`. `<StatusBar />` at top.

**Scroll body** (`className="st-scroll"`, absolute inset 0, `top 54`, `overflow auto`, `padding "8px 20px 110px"`):

1. **Header row** (flex, align center, space-between):
   - Back button: `36×36`, `borderRadius 999`, `background T.fieldFill`, grid-centered, `onClick → go('briefing')`, `Ic name="back" s=17 c=T.text2`.
   - `<Chip tone="neutral">Step 3 of 4</Chip>`.
   - Right button: `36×36` radius999 `T.fieldFill`, `onClick → go('library')` (close/library icon).
2. **Title block** (marginTop 18):
   - `<Label>Detail tier</Label>`.
   - `"How much detail?"` — **28 / 720**, ls −0.9, `T.ink`, marginTop 6.
   - Subtitle `"Matches Apple's PhotogrammetrySession tiers. Re-process anytime."` — 13.5, `T.text2`, marginTop 8.
3. **Scale strip** Card `radius 18 padding 16 marginTop 14`:
   - Labels row (mono **10**, ls 1, `T.text3`, space-between, marginBottom 12): `FAST` · `BALANCED` · `ARCHIVE`.
   - Gradient track: `height 6`, `borderRadius 99`, `background linear-gradient(90deg, T.text4, T.accent)`.
   - Dots row (`TIERS.map`, space-between, marginTop −1): each tier a `button` (`onClick → setSel(id)`): dot `13×13` radius99 marginTop −10, `background: on?T.accent:T.card`, `border 2px solid ${on?T.accent:T.lineStrong}`, `boxShadow: on ? "0 0 0 3px T.accentSoft" : none`; below it `{name.toUpperCase()}` (mono **9.5**, `on?T.ink:T.text3`, weight `on?700:500`).
4. **Selected tier card** (marginTop 14): `<TierCard tier={tier} selected onPick={()=>{}} />` (full, non-compact, always shown selected).
5. **Two other tiers** (flex column, gap 8, marginTop 12): `TIERS.filter(t=>t.id!==sel).slice(0,2)` → compact rows:
   - `<Card radius={14} onClick={() => setSel(t.id)} className="st-tap" style={{ padding:'12px 14px', flex row align center gap 12 }}>`: `<TierPreview tier size={40} />`, then column [`name` 14/650 ink + `"{tris} tris · {size} · ~{time}"` mono 10.5 text3], then `Ic name="chev" s=15 c=T.text3`.

**Sticky footer** (absolute bottom 28, left/right 20):
`<Button kind="accent" full size="lg" onClick={() => go('viewfinder')}>` → `Ic name="bolt" s=16 c=T.onAccent` + ` Capture at {tier.name}` (e.g. "Capture at Medium").

---

## PadQuality (iPad)

Root: absolute fill `background T.bg`. `<PadStatusBar />` at top. Content container absolute inset 0, `top 30`, flex column, `padding 24` (fixed, **no scroll** — the tier grid flexes to fill).

1. **Header row** (flex, align center, space-between):
   - Left group (flex, align center, gap 12): back button `38×38` radius999 `T.fieldFill`, `Ic back s=17 c=T.text2`, `onClick → go('briefing')`; text block `<Label>New Scan · Step 3 of 4</Label>` over `"Choose detail tier"` (**17 / 700**, ls −0.3, ink, marginTop 2).
   - `<StepTabs active={2} />` (center progress tabs).
   - `<Button kind="accent" size="sm" onClick={() => go('viewfinder')}>` → `Ic bolt s=16 c=T.onAccent` + ` Capture at {tier.name}`.
2. **Two-column grid** (`gridTemplateColumns "1fr 1fr"`, gap 16, marginTop 18):
   - **Left Card** `radius 22 padding 22`: `<Label>Apple PhotogrammetrySession</Label>`; headline `"Five tiers,<br/>same source frames."` (**32 / 720**, ls −1.1, marginTop 8, lineHeight 1.02); body `"3DSeen captures once at Raw and re-derives every lower tier on demand. You'll never need to re-scan."` (14, text2, marginTop 12, lineHeight 1.45); stats row (flex, gap 28, marginTop 18) over `[['Captured frames','340',T.ink], ['Raw archive','1.1 GB',T.ink], ['Re-process','Unlimited',T.good]]` → `<Label>{k}</Label>` + value (**22 / 720**, color `c`, ls −0.5, marginTop 3).
   - **Right Card** `radius 22 padding 22`: `<Label color={T.accentText}>Fidelity comparison</Label>`; `<FidelityChart sel={sel} />` (marginTop 14).
3. **5-up tier grid** (`gridTemplateColumns "repeat(5, 1fr)"`, gap 12, `flex 1`, `minHeight 0`, marginTop 16): `TIERS.map(t => <TierCard tier={t} selected={t.id===sel} compact onPick={setSel} />)` — all five compact cards in a row, each full-height.
4. **Info Card** `radius 14 padding "10px 16px" marginTop 16` (flex row align center gap 10): `Ic name="info" s=16 c=T.accent` + text (12.5, text2): `"For commercial fidelity, capture at `**`Raw`**` and view/share at `**`Full`**`. Re-derive in the library anytime — your iPhone keeps the archive, your Mac does the heavy lifting."` (the words **Raw** and **Full** bold in `T.ink`).

---

## Interactions / navigation
- Back (`Ic back`) → `go('briefing')`.
- Phone top-right button → `go('library')`.
- Selecting a tier: phone scale dots and the two "other" rows call `setSel(id)`; iPad tier cards call `setSel` via `onPick`. Selection drives the highlighted `TierCard`, the FidelityChart active point, and the footer button label `Capture at {name}`.
- Primary CTA (`Capture at {name}`) → `go('viewfinder')` (advances to live capture).
- iPad `StepTabs active={2}` reflects step 3 of 4.

## Device differences
- **Phone**: single scrolling column — header, copy, the FAST↔ARCHIVE scale slider, the selected full card, two collapsed alternative rows, sticky bottom CTA. Only 3 of 5 tiers visible at once (selected + 2).
- **iPad**: no scroll; an explanatory hero Card + a FidelityChart Card side-by-side, then **all 5 tiers** as compact cards in one row, plus a footer info Card. CTA lives inline in the header (size sm) instead of a sticky full-width button.

## Dynamic
- Selection state recolors: TierCard (accentSoft bg + accent ring), scale dots (accent fill + 3px accentSoft glow ring), FidelityChart point (r 7, accent fill).
- FidelityChart plots PSNR (dB) per tier as a rising curve; the selected tier's dot enlarges.

## Implementation notes for SwiftUI
- The **scale slider** (FAST/BALANCED/ARCHIVE) is a custom gradient track (`text4→accent`) with 5 selectable dots overlapping the bar at `marginTop -10`; the active dot gets a 3px `accentSoft` halo. Build as a `ZStack` of a `Capsule().fill(LinearGradient)` plus an `HStack` of dot buttons pinned with negative offset.
- **FidelityChart**: map `psnr 18…46` to vertical position with `y=(h−28)−((psnr−18)/28)*(h−56)`, x evenly across `55 … w−10`. Draw the connecting polyline in `accentLine`, dashed gridlines `2 4`, labels in mono. Recompute the active point radius from `sel`.
- TierCard must support both `compact` (iPad 5-up, fixed height, 17px name, 13px stats) and full (phone, 20px name, use-text, 15px stats) from one view via a `compact` flag.
- Keep every literal: tier names/tags/specs, the two headlines ("How much detail?" / "Five tiers, same source frames."), all stat triples, and the info-card sentence with bold **Raw**/**Full**.
- Numerics (tris, sizes, times, psnr, 340, 1.1 GB) use the `st-num` monospaced-digit treatment.
