# Viewfinder — SwiftUI implementation spec

Source: `docs/design-ref/screens/viewfinder.jsx`
Exports (no Mac variant): `PhoneViewfinder`, `PadViewfinder`, plus helpers `CameraFeed`, `ARBox`.
File intent (header comment): *"live capture scan (iPhone · iPad). Liquid Glass: dark glass overlays float over the camera feed, telemetry is a single tidy capsule, nothing clips."*

This is the **live-capture camera screen**: a full-bleed simulated camera feed with a ceramic-bust subject, an AR bounding box, and floating **dark-tone Glass** HUD clusters. All Glass here uses `tone="dark"` (white text on translucent dark glass). Everything is absolutely positioned over the feed — there is **no scroll**; the whole screen is a fixed overlay stack.

---

## Shared building blocks (define once)

### CameraFeed(vb = "0 0 402 874")
The faux camera background, stacked bottom→top:
- Root: fill parent, `overflow hidden`, background `#0B0A09`.
- Layer 1 (full): radial gradient `radial-gradient(58% 70% at 50% 54%, #1f1914 0%, #0d0b09 60%, #060504 100%)` — warm pool of light center-low.
- Layer 2 (left 60% width, full height): `radial-gradient(ellipse at 0% 30%, rgba(255,214,168,0.12), transparent 60%)`, `mixBlendMode: screen` — warm key-light glow from the left.
- SVG subject (viewBox = `vb`, `preserveAspectRatio="xMidYMid slice"`), a stylized ceramic bust on a plinth:
  - `defs`: radialGradient **cf-b** (cx .42 cy .34 r .66; stops `0% #EBCFA9`, `42% #9B7A5B`, `100% #1c130c`); radialGradient **cf-h** (cx .34 cy .24 r .4; stops `0% rgba(255,228,190,0.6)`, `100% rgba(255,228,190,0)`).
  - Contact shadow: `ellipse cx201 cy600 rx120 ry16 fill rgba(0,0,0,0.65)`.
  - Plinth: `rect x135 y560 w132 h44 rx3 fill #15110d`.
  - Body: `path … fill url(#cf-b)` (tapered vase/torso silhouette).
  - Head/bust: `ellipse cx201 cy300 rx56 ry72 fill url(#cf-b)`.
  - Recess: `path … fill #241a12` (dark interior of the face/neck).
  - Specular highlight: `ellipse cx184 cy288 rx38 ry52 fill url(#cf-h)`.
- Then renders `children` (overlay layers) above the SVG.

### ARBox(vb, box=[x1,y1,x2,y2], dim, accent="#fff")  — `k = 20`
SVG sized to parent, `viewBox=vb`, `pointer-events: none`. Draws:
- Faint bounding rect: `rect x=x1 y=y1 w=x2−x1 h=y2−y1 rx8 fill=none stroke=rgba(255,255,255,0.20) strokeWidth=1`.
- Four rounded **corner brackets**, mapped over `[[x1,y1,1,1],[x2,y1,-1,1],[x1,y2,1,-1],[x2,y2,-1,-1]]` (corner, signX, signY):
  `path d="M{x+sx*k} {y} L{x+sx*6} {y} Q {x} {y} {x} {y+sy*6} L{x} {y+sy*k}" stroke={accent} strokeWidth="2.4" fill="none" strokeLinecap="round"` — an L with a 6px rounded elbow and 20px arms.
- Dimension **caliper** on the left: vertical `line x1={x1−13} y1={y1} x2={x1−13} y2={y2}` plus end caps, and the `{dim}` text label (e.g. `"14.2 cm"` phone / `"18.4 cm"` pad) to the left, end-anchored.

### Shutter(size = 74, onClick)
Round white shutter button: `width=height=size`, `borderRadius 99`, `padding 5`, `background #fff`, `boxShadow: inset 0 0 0 2.5px rgba(0,0,0,0.85), 0 4px 18px rgba(0,0,0,0.45)`. Inner record swatch: child div `100%×100%`, `borderRadius 9`, `background T.bad` (rounded-square red = recording).

### Telemetry(items)
A single dark Glass capsule (`tone="dark"`, `radius 15`, `padding "9px 4px"`). Maps `items` = `[label, value, color?]` into equal-width cells; each cell after the first has a `0.5px` hairline left border `rgba(255,255,255,0.12)`. Per cell: small uppercase mono label (≈8.5px, letterSpacing, white-55%) over a value (`st-num`, mono **13 / 700**, color = `color || #fff`, marginTop 3, lineHeight 1).

### DLabel(children, color)
Tiny dark-glass label: mono **9.5 / 600**, letterSpacing **1.3**, `textTransform uppercase`, color = `color || rgba(255,255,255,0.55)`.

---

## PhoneViewfinder (iPhone, 402×874)

Root: absolute fill. Layer order:
1. `<CameraFeed />` (default vb `0 0 402 874`).
2. `<ARBox vb="0 0 402 874" box={[124,250,278,548]} dim="14.2 cm" accent="#fff" />`.
3. `<StatusBar tone="light" />` (white status text for dark feed).

Then four floating clusters (all absolutely positioned):

### A. Top bar — back + REC capsule (top 58, left/right 16; flex row, align center, gap 8)
- **Close** Glass: `tone=dark radius=13`, `40×40`, grid-centered, `cursor pointer`, `onClick → go('briefing')`. Icon `Ic name="close" s=16 c="#fff"`.
- **REC capsule** Glass: `tone=dark radius=13`, `flex 1`, `height 40`, row align center gap 9, padding `0 13px`:
  - pulsing dot `7×7` radius99 `background T.bad`, `animation: st-pulse 1.4s infinite`.
  - `"REC"` mono **11 / 700**, `#fff`, letterSpacing 0.5.
  - `"00:42.3"` (`st-num`) mono **12 / 600** `#fff`.
  - spacer `flex 1`.
  - `"OBJ · FULL · 4K"` (`st-num`) mono **10** `rgba(255,255,255,0.6)`.
- **Thermal** Glass: `tone=dark radius=13`, `height 40`, row align center gap 5, padding `0 12px`: `Ic name="thermal" s=13 c=rgba(255,255,255,0.7)` + `"34°"` (`st-num`) mono **11** `#fff`.

### B. Telemetry capsule (top 106, left/right 16)
`<Telemetry items={[['LUX','1840'], ['DIST','42cm'], ['SHARP','0.94','#7FD9A6'], ['MOTION','34°/s','#E7B24C']]} />`
→ 4 equal cells: LUX 1840, DIST 42cm, SHARP 0.94 (green value), MOTION 34°/s (amber value).

### C. Compact coverage tile (top 166, right 16, width 132)
Glass `tone=dark radius=16 padding=12`:
- Header row: `DLabel` "Coverage" + a small frame count label (right).
- `<CoverageSphere size={104} />` centered.
- Bottom row (flex, align flex-end, justify space-between):
  - Big % readout: `72` at **30 / 720** `#fff`, with `%` at smaller size `rgba(255,255,255,0.4)`.
  - 3-line legend (12px? rendered at the compact 9.5 scale, lineHeight 1.5, weight 600), right-aligned:
    - `16 strong` — color `#7FD9A6`
    - `3 weak` — color `#E7B24C`
    - `3 gap` — color `#FF8A7E`

### D. Object label under AR box (top 560, left 16)
- `DLabel color="#9FC0FF"` → `"AI Scene · Auto-Pilot"`.
- Object name `"Ceramic bust"` (≈15 / 700, white).
- Dimensions/confidence line (`st-num`, mono ≈10, white-55%): `"14.2 × 10.8 × 14.2 cm · conf 0.94"`.

### E. Bottom dock (bottom 28, left/right 16; flex column, gap 9)
- **Hint pill** (centered child): Glass `tone=dark radius=99`, row align center: amber speed icon (`#E7B24C`) + coaching text `"Slow down · 34 → under 30°/s"` (≈12.5 / 650).
- **Dock Glass** `tone=dark radius=20 padding "14px 16px"`, row align center:
  - **Mode block** (left, width 88): `DLabel` "Mode" / value `"Object"` (≈18–20 / 720 white) / sub `"FULL · 4K"` (mono, white-50%).
  - **Shutter** (center, `flex 1`, centered): `<Shutter onClick={() => go('review')} />` (default size 74). **This is the capture/stop action → navigates to `review`.**
  - **ETA block** (right, width 88, right-aligned): `DLabel` "ETA · Mac" / `"1:52"` (`st-num` ≈26 / 720) / `"local 6:42"` (mono ≈10, white-50%).

---

## PadViewfinder (iPad, 1194×834)

Root: absolute fill. Layer order:
1. `<CameraFeed vb="0 0 1194 834" />`.
2. `<ARBox vb="0 0 1194 834" box={[472,222,722,648]} dim="18.4 cm" accent="#fff" />`.
3. `<StatusBar tone="light" />`-equivalent.

The iPad spreads the HUD into a **top bar + two side rails + a bottom dock** (vs the iPhone's stacked clusters).

### Top bar (top 38, left/right 20, height 46; flex row, gap 10)
- **Close** Glass `tone=dark radius=14`, `46×46`, grid center, `onClick → go('briefing')`, `Ic close s=17 c="#fff"`.
- **REC capsule** Glass `tone=dark radius=14`, `height 46`, row align center gap 12, padding `0 18px`:
  - pulsing dot `8×8` `T.bad` (`st-pulse 1.4s`).
  - `"REC"` mono **12 / 700** `#fff` ls 0.5.
  - `"00:42.318"` (`st-num`) mono **13 / 600** `#fff`.
  - `0.5px` vertical divider, height 18, `rgba(255,255,255,0.22)`.
  - `"OBJECT · FULL · 4096²"` (`st-num`) mono **11** `rgba(255,255,255,0.7)`.
- spacer `flex 1`.
- **Telemetry strip** Glass `tone=dark radius=14`, `height 46`, align stretch, padding `0 4px`. Maps `[['THERMAL','34°','thermal'], ['LIGHT','1840 lx','light'], ['BATTERY','78%','battery'], ['STORAGE','244 GB','download']]` → cells (column, justify center, padding `0 14px`, hairline left border `0.5px rgba(255,255,255,0.12)` for i>0). Per cell: row [`Ic name={ic} s=11 c=rgba(255,255,255,0.55)` + key mono **8** white-50% ls 1] over value (`st-num`, mono **13 / 600** white, marginTop 2).

### Left rail (top 100, left 20, bottom 158, width 252; column, gap 10)
- **Coverage** Glass `tone=dark radius=18 padding=16`:
  - `<DLabel>Coverage</DLabel>`.
  - `<CoverageSphere size={184} />` centered (marginTop 4).
  - Bottom row (align flex-end, space-between): big `72%` (`st-num` **44 / 720**, ls −1.6, white, with `%` at 18 white-50%) and 3-line legend (12 / 600): `16 strong` `#7FD9A6`, `3 weak` `#E7B24C`, `3 gap` `#FF8A7E`.
- **Second left-rail Glass** (surface/AI-Pilot guidance card; dark Glass) — the iPhone hint pill's expanded sibling.

### Right rail (top 100, right 20, bottom 158, width 272; column, gap 10)
- **Live frame / PSNR** Glass `tone=dark radius=18 padding=16`:
  - Row (align flex-end, space-between): `<DLabel>Live frame · 0247</DLabel>` over `38.7` (`st-num` **26 / 720**, ls −0.8) + `"dB PSNR"` (12, white-50%, baseline-aligned); and `<Spark values={[33,34,32,35,36,37,38,38.7,38.5,38.4,38.7,38.6]} w={104} h={34} color="#9FC0FF" />`.
  - `0.5px` divider `rgba(255,255,255,0.12)`, margin `14px 0`.
  - 4-col grid (gap 12): `[['SHARP','0.94'], ['PARALLAX','8.4°'], ['DIST','42cm'], ['FOCUS','0.99']]` → key (mono **8.5** white-50% ls 0.6) over value (`st-num`, mono **13.5 / 600** white).
- **Histogram** Glass (second right-rail card) — frame-strip / histogram panel labeled `"Frame strip · recent"`.

### Bottom dock (bottom 20, left/right 20, height 126; flex row, gap 10)
Three dark Glass panels side by side:
- **AI scene** Glass (left).
- **Frame strip** Glass (center) — `<DLabel>Frame strip · recent</DLabel>` over a frame thumbnail strip.
- **ETA / Shutter** Glass `tone=dark radius=18 padding=16 width=252`, row align center gap 14:
  - `flex 1` centered `<Shutter size={84} onClick={() => go('review')} />`.
  - Right block: `<DLabel style={{textAlign:'right'}}>ETA · Mac</DLabel>`, `"1:52"` (`st-num` **26 / 720**, ls −1), `"local 6:42"` (`st-num` mono **10** white-50%).

---

## Interactions / navigation
- Close (X) → `go('briefing')` (both devices).
- Shutter (both devices) → `go('review')` — capture/stop ends the session and moves to post-capture review.
- No other taps; the rails/telemetry are read-only HUD.

## Dynamic / animated
- REC dot: `st-pulse 1.4s infinite` (opacity/scale pulse). Recording timecode is shown statically (`00:42.3` / `00:42.318`) but in a live app would tick on the `st-num` font.
- CoverageSphere is a live coverage gauge (fills as the user orbits the subject); the % and strong/weak/gap counts (72%, 16/3/3) are its live readout.
- Spark (PSNR sparkline) animates per frame; FrameStrip scrolls recent frames.
- ARBox corner brackets + caliper track the detected object (here static at the given `box`/`dim`).

## Implementation notes for SwiftUI (fidelity-critical)
- **Camera-feed glass**: replicate the dark feed with two stacked `RadialGradient`s (the second clipped to the left 60% with a `.blendMode(.screen)`), then the bust as a `Canvas`/`Shape` group using the two radial fills (`cf-b`, `cf-h`). The HUD panels are `.ultraThinMaterial`-style but **dark-tinted** — use a dark translucent fill (`Color.black.opacity(~0.35)` + `.background(.ultraThinMaterial)` darkened) with a subtle 0.5px white-12% inner stroke; do **not** use the light system material or the white text will lack contrast. Match the design's `Glass tone="dark"` exactly (white text, white-55%/white-50% secondaries).
- **CoverageSphere / coverage HUD**: this is the trickiest. It is a 3D-ish dome gauge whose fill = capture coverage. Reproduce as a sphere of latitude/longitude cells colored strong(`#7FD9A6`)/weak(`#E7B24C`)/gap(`#FF8A7E`); keep the exact legend wording and the big `72%` readout. Phone uses size 104 (compact) / Pad uses 184; the same component must scale.
- **ARBox** brackets must be rounded-elbow Ls (6px `Q` curve, 20px arms, `strokeWidth 2.4`, round caps), not sharp corners. Convert the box coords from the SVG viewBox space to view points (phone vb 402×874, pad 1194×834).
- **Absolute layout, no scroll**: everything is pinned with explicit insets — use a `ZStack` with `.position`/`.padding` from the safe-area edges (top 58/38, bottom 28/20, sides 16/20). Nothing scrolls; nothing should clip (the comment stresses this).
- **Telemetry capsule** needs equal-width cells with hairline dividers and no clipping at small widths — use a fixed-height `HStack` with `Divider().frame(width:0.5)` tinted white-12%.
- Color tokens: `T.bad` = record red, `T.good`-ish greens are the literal `#7FD9A6`; amber `#E7B24C`; gap `#FF8A7E`; accent-blue text `#9FC0FF`. Feed bg literals `#0B0A09`, gradient stops as listed.
- Mono = `T.mono`; the `st-num` class = tabular/monospace numerics — use a monospaced-digit font for all timecodes, PSNR, %, and dimensions.
