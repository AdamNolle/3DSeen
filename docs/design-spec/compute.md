# Compute pipeline & Mac handoff — SwiftUI implementation spec

Source: `studio/screens/compute.jsx` (fully verbatim). Exports `PhoneCompute`, `PadCompute`, `MacCompute`. Screen purpose: choose where to render the captured scan (stay on device, or hand off to a Mac over MultipeerConnectivity), and — on Mac — watch the reconstruction pipeline run.

All color names are `T.*` design tokens. Accent = `#2D68F0` (light) / `#5E9BFF` (dark). Fonts: `T.sf` (UI), `T.mono` (numeric, used everywhere a `className="st-num"` appears).

---

## Shared sub-components (used by multiple variants)

### `HandoffArc` — animated particle-beam connector
- An SVG quadratic Bézier from `(10, h/2)` to `(w-10, h/2)` with control point `(w/2, h/2 - lift)` where `lift = height*0.5` (arc bows upward by half its height).
- Base path: stroke `T.line`, `strokeWidth 1.4`, `strokeDasharray "2 6"`, round caps, fill none (a faint dotted guide).
- `dots` circles (default 26) sampled along the curve at parameter `t = i/(dots-1)`.
  - Each dot is "active" when `t <= progress`.
  - Active dot: radius `2.6`, fill `T.accent`, opacity `1`.
  - Inactive dot: radius `1.6`, fill `T.text3`, opacity `0.5`.
- Props/defaults: `progress=0.58`, `width=360`, `height=70`, `dots=26`. SVG `overflow: visible`, `display: block`.
- SwiftUI: a `Canvas` or `Path` (quadratic curve) plus dots positioned via the quadratic Bézier formula. The fill/size transition between active and inactive states is the "beam fill" animation as progress advances.

### `COMPUTE_OPTIONS` data (the two render targets)
- `mac`: id `mac`, name **"Mac handoff"**, icon `laptop`, tag **"M-series Neural Engine · no thermal cap"**, `best: true` (shows FASTEST chip). Stats (4): `ETA 1:52` (color `T.accentText`), `Speed 3.6×` (default color), `Battery 0%` (color `T.good`), `Quality Full` (color `T.good`).
- `local`: id `local`, name **"On-device"**, icon `chip`, tag **"RealityKit · auto-throttle · offline-ready"**, no best flag. Stats (4): `ETA 6:42` (default), `Speed 1.0×` (default), `Battery ~22%` (color `T.warn`), `Throttle Auto` (color `T.good`).

### `OptionCard` — selectable render-target card (`big` variant for Pad)
- Button, full width, `textAlign left`. Radius `big ? 20 : 18`, padding `big ? 18 : 15`.
- Background: selected → `T.accentSoft`, else `T.card`. Border `0.5px solid` (selected `T.accentLine` else `T.line`). Box shadow selected adds `0 0 0 1px T.accentLine` ring plus `T.cardShadow`; unselected just `T.cardShadow`.
- Header row (gap 11, center-aligned):
  - Icon tile `38×38`, radius `11`, background selected `T.accent` else `T.fieldFill`; unselected has `inset 0 0 0 0.5px T.line`. Contains `Ic name={opt.icon} s=20` colored `T.onAccent` (selected) / `T.text2`.
  - Text column: title row = `opt.name` at `16px / weight 700 / letterSpacing -0.3 / T.ink`, plus when `best` an accent `Chip` with text **FASTEST** at `fontSize 9`. Below: `Label` (the `opt.tag`), color selected `T.accentText` else `T.text3`, `marginTop 3`.
- Stats row: `marginTop 14`, flex gap 10, each stat in a `flex:1` cell rendered as `<Stat k v c size="sm" />`. Color comes from the option's stat tuple (functions returning a token, or none).

### Device glyphs
- `PhoneGlyph` (default `w=46`): a phone-shaped body `w × w*1.6`, radius 10, background `T.ink`, padding 3, big shadow `T.cardShadowLg`. Inner screen radius 8 holds `Stage(radius 8)` with `HeroModel`. Below: label at `12.5px / weight 650 / T.ink / marginTop 8`, then a `Label` (sub) colored `T.accentText`.
- `MacGlyph` (default `w=92`): a laptop screen body `w × w*0.64`, radius 7, background `T.ink`, padding 3, shadow `T.cardShadowLg`; inner radius 4 holds `Stage(radius 4)` + `HeroModel`. A "base/lid hinge" bar `w*1.18 × 4` in `T.lineStrong`, radius `0 0 3px 3px`, centered. Then label `12.5px / 650 / T.ink / marginTop 7` and a `Label` (sub) colored `T.text3`.

---

## iPhone — `PhoneCompute`

Single scrolling column on `T.bg`. Step 4 of 4 of the capture flow.

### Layout hierarchy (top → bottom)
1. **`StatusBar`** (pinned, the standard iOS status bar component).
2. **Scroll body** (`st-scroll`): absolute inset 0, `top: 54`, `overflow auto`, padding `8px 20px 110px` (bottom 110 leaves room for the pinned CTA).
   1. **Nav row** (space-between):
      - Left: circular back button `36×36`, radius 999, background `T.fieldFill`, `Ic back s=17 c=T.text2`. Tap → `go('review')`.
      - Center: neutral `Chip` text **"Step 4 of 4"**.
      - Right: circular close button `36×36`, `Ic close s=16 c=T.text2`. Tap → `go('library')`.
   2. **Title block** (`marginTop 18`):
      - `Label` **"Where should we render?"**
      - Title **"Compute pipeline"** at `28px / weight 720 / letterSpacing -0.9 / T.ink / marginTop 6`.
      - Subtitle **"Stay on iPhone, or hand off to your Mac on Wi-Fi."** at `13.5px / T.text2 / marginTop 8`.
   3. **Handoff card** (`Card radius=22`, padding 20, marginTop 14): a row (space-between, center):
      - `PhoneGlyph` label **"iPhone 16 Pro"**, sub **"SCAN · 1.1 GB"**.
      - Middle column (`flex 1`, padding `0 6px`): `HandoffArc width=150 height=54 progress=0.62`, then a mono caption **"MULTIPEER · 1.2 Gbps"** centered, `9.5px`, `T.accentText`, letterSpacing 1, marginTop 2.
      - `MacGlyph w=84` label **"MacBook Pro"**, sub **"M4 MAX"**.
   4. **Option list** (column, gap 10, marginTop 12): `OptionCard` for `mac` then `local`. Selected state bound to `sel` (initial **`'mac'`**).
3. **Pinned bottom CTA**: absolute `bottom 28, left/right 20`. `Button kind="accent" full size="lg"`. Icon + label switch on `sel`:
   - `sel === 'mac'` → icon `laptop` (`s=17 c=T.onAccent`), text **"Hand off to MacBook Pro"**.
   - else → icon `chip`, text **"Compute on iPhone"**.
   - Both branches call `go('viewer')` (the ternary resolves to `'viewer'` either way).

### Interactions
- Back → `review`; close → `library`; option cards set `sel`; CTA → `viewer`.

---

## iPad — `PadCompute`

A big single hero card filling the screen, illustrating the hub-and-spoke handoff with a live streaming visualization.

### Layout hierarchy (top → bottom)
1. **`PadStatusBar`** (pinned).
2. **Content** (absolute inset 0, `top 30`, flex column, padding 24):
   1. **Header row** (space-between, center):
      - Left group (gap 12): back button `38×38` round, `T.fieldFill`, `Ic back s=17 c=T.text2` → `go('review')`; then a two-line title block: `Label` **"Step 4 of 4 · Compute pipeline"** over **"Where should we render?"** at `17px / 700 / letterSpacing -0.3 / T.ink / marginTop 2`.
      - Right group (gap 8): two buttons — `secondary size=sm` **"Compute on iPad"** (icon `chip s=15 c=T.ink`) → `go('viewer')`; `accent size=sm` **"Hand off to Mac"** (icon `laptop s=15 c=T.onAccent`) → `go('viewer')`.
   2. **Hero card** (`Card radius=26`, `flex 1`, padding 28, marginTop 18, column, `overflow hidden`, relative):
      - **Top row** (space-between, items flex-start):
        - Left text: `Label` (color `T.accentText`) **"Hub & spoke"**; headline **"Capture here."** / **"Render there."** (second line colored `T.accentText`) at `42px / weight 730 / letterSpacing -1.6 / lineHeight 1`; paragraph at `14px / T.text2 / maxWidth 430 / lineHeight 1.45`: **"MultipeerConnectivity streams the raw scan to your Mac so the M-series Neural Engine renders without thermal limits — while your iPad stays cool."**
        - Right: connection `Card inset radius=16`, padding 16, `width 280`:
          - Status row: green dot `9×9` (`T.good`) + **"Connected to "Adam's MBP""** at `13px / 700 / letterSpacing -0.2 / T.ink`.
          - Mono line **"peer · 192.168.1.42 · 1.2 Gbps"** at `10.5px / T.text3 / marginTop 4`.
          - Stats row (gap 18, marginTop 14): `Stat Ping 4 ms`, `Stat Loss 0 %`, `Stat Sent 1.1 GB` (color `T.accentText`), all `size=sm`.
      - **Middle visualization** (`flex 1`, row, space-around, padding `10px 50px`):
        - **Left device**: a phone-ish device `180×128`, radius 16, `T.ink`, padding 6, shadow `T.cardShadowLg`; inner radius 10 holds `Stage(10)` + `HeroModel 180×128`. Caption **"iPad Pro M4"** at `14px / 700 / T.ink / marginTop 10`; `Label` **"SCAN COMPLETE · 1.1 GB"** color `T.accentText`.
        - **Center stream** (`flex 1`, padding `0 20px`, maxWidth 460):
          - A centered `Glass radius=999` pill (padding `6px 14px`): `Ic bolt s=13 c=T.accent`, then mono **"STREAMING · 58%"** (`12px / 700 / T.ink`), then mono **"652 / 1124 MB"** (`11px / T.text3`).
          - `HandoffArc width=420 height=90 progress=0.58`.
          - Below, centered chips (gap 8): three neutral mono `Chip`s **"AES-256"**, **"multipeer"**, **"ETA 0:38"** at `10.5px`.
        - **Right device** (the Mac, receiving): screen `200×128`, radius 9, `T.ink`, padding 5; inner radius 5 holds `Stage(5)` + `HeroModel 200×128 material="wire"` (wireframe = still reconstructing). Hinge bar `64×5` `T.lineStrong`. Caption **"MacBook Pro M4 Max"** `14px / 700`; `Label` **"RECEIVING · NEURAL ENGINE"** color `T.accentText`.
      - **Bottom option grid** (2 columns `1fr 1fr`, gap 14): `OptionCard big` for `local` (left) then `mac` (right). Note: order is reversed vs iPhone (local first). Selected bound to `sel` (initial `'mac'`).

### Device differences vs iPhone
- No pinned CTA; the two actions live as small buttons in the header and the big option cards sit at the card bottom.
- Adds the live connection telemetry card and the full streaming visualization (phone → arc → mac) that iPhone collapses into one small card.
- Option cards are `big` and laid out in a 2-up grid (local, mac) instead of a 1-up stack (mac, local).

---

## Mac — `MacCompute`  (compute dashboard: receiving + processing)

A 3-pane desktop window: left pipeline rail (320), center live preview (flex), right telemetry panel (300). Reached from the Library (the Mac handoff target).

### Title/toolbar bar (pinned, height 52)
- `borderBottom 0.5px T.line`, background `T.card2`, padding `0 18px 0 84px` (the 84px left inset clears the macOS traffic-light buttons / window controls).
- Left → right: back chip-button (height 30, padding `0 10px`, radius 8, `T.fieldFill`, `Ic back s=15 c=T.text2`, text **"Library"** `13px / 600 / T.text2`) → `go('library')`; vertical `Rule` height 22; a pulsing accent status dot `8×8` (`T.accent`, ring `0 0 0 3px T.accentSoft`); window title **"Compute · Celestial Bust"** (`15px / 700 / letterSpacing -0.3 / T.ink`); accent `Chip` (`Ic laptop s=13 c=T.accentText` + **"Handoff from iPhone"**); spacer; neutral `Chip` (`Ic clock s=13 c=T.text2` + **"ETA 1:52"**).

### Body (flex row, fills remaining height)

**1. Pipeline rail** — width 320, `borderRight 0.5px T.line`, background `T.card2`, padding 22, flex column.
- `Label` **"Pipeline · RealityKit on M4 Max"**.
- Vertical stepper (`marginTop 16`, flex 1) over `PIPELINE` (6 stages). Each step is a row (gap 12):
  - Left gutter: a `26×26` round node + a connector line to the next node.
    - `done` node: background `T.good`, contains `Ic check s=14 c=#fff sw=2.6`.
    - `active` node: background `T.accentSoft`, ring `0 0 0 3px T.accentSoft`, contains an `8×8` accent dot.
    - pending node: background `T.fieldFill`, contains the 1-based index number (`11px / 700 / T.text3`, mono).
    - Connector: `width 2`, `minHeight 18`, color `done ? T.good : T.line`, marginTop 6.
  - Right content (paddingTop 2): step title `14px / 650`, color `T.ink` if active/done else `T.text2` (rendered via `dangerouslySetInnerHTML` so the literal `&amp;` decodes to `&`); subtitle `11px / T.text3 / mono / marginTop 2`; and if `active`, a `Meter value={pct} color=T.accent height=5` (marginTop 8).
  - **PIPELINE data** (order, label, subtitle, pct, state):
    1. `Frame ingest` — "334 frames · aligned" — pct 1 — **done**.
    2. `Sparse cloud` — "1.2M points · SfM" — pct 1 — **done**.
    3. `Dense reconstruction` — "MVS · depth fusion" — pct **0.74** — **active**.
    4. `Meshing` — "Poisson · 4.2M tris" — pct 0 — pending.
    5. `Texturing` — "8K PBR · albedo/normal" — pct 0 — pending.
    6. `Optimize & export tiers` (literal source `Optimize &amp; export tiers`) — "decimate · UV · USDZ" — pct 0 — pending.
- Bottom: `Card inset radius=14` padding 14 — `Label` (color `T.accentText`) **"Live throughput"**; stats row (gap 16, marginTop 10): `Stat Frames/s 184`, `Stat Elapsed 2:38`, `Stat Remaining 1:52` (color `T.accentText`), all `size=sm`.

**2. Live preview** — `flex 1`, relative, `borderRight 0.5px T.line`.
- Full-bleed `Stage` with `HeroModel w=620 h=620 material="wire"` (wireframe = mid-reconstruction).
- Top-left overlay: accent `Chip` containing a `6×6` accent dot with CSS animation `st-pulse 1.4s infinite`, text **"Dense reconstruction · 74%"**.
- Bottom-center overlay: `Glass radius=16` (padding `12px 18px`, flex gap 26): `Stat Points 3.1M`, `Stat Depth maps 334`, `Stat Confidence 0.96` (color `T.good`), `Stat Tris (est) 4.2M`, all `size=sm`.

**3. Telemetry panel** — width 300, scrollable (`st-scroll`), background `T.card2`, padding 22, column gap 18.
- **Hardware** section (`Label` "Hardware"): 4 labeled meters (column gap 14, marginTop 14). Each row: name (`12.5px / 600 / T.ink`) + right-aligned mono reading (`11px / T.text2`) over a `Meter height=5`:
  - **Neural Engine** — value 0.92 — color `T.accent` — reading **"38 TOPS"**.
  - **GPU · 40-core** — 0.78 — `T.accent` — **"76%"**.
  - **CPU · 16-core** — 0.34 — `T.text2` — **"34%"**.
  - **Unified memory** — 0.46 — `T.text2` — **"22 / 48 GB"**.
- `Rule`.
- **Thermals** section (`Label` color `T.good`, "Thermals"): stats row (gap 16, marginTop 12): `Stat SoC 58 °C` (color `T.good`), `Stat Fans 2400 rpm`, `Stat Power 46 W`, all `size=sm`.
- `Rule`.
- **Transfer log** section (`Label` "Transfer log"): column (gap 7, marginTop 10) of timestamped entries. Each: mono timestamp (`10.5px / T.text4 / width 56`) + message (`12px / 500`, colored per-row):
  - `14:02:11` — **"Received 334 frames"** — `T.good`.
  - `14:02:14` — **"Sparse cloud built"** — `T.good`.
  - `14:04:49` — **"Dense MVS running…"** — `T.accentText`.
  - `—` — **"Meshing queued"** — `T.text3`.
- Spacer, then full-width `Button kind="accent"` (`Ic cube s=16 c=T.onAccent` + **"Open when ready"**) → `go('viewer')`.

### Device differences
- Mac is the *destination* view (not a chooser): no "where to render" decision; instead a running dashboard. The phone/pad chooser screens never show the pipeline stepper, hardware meters, thermals, or transfer log.
- 3-pane fixed layout with 84px traffic-light inset, vs the device variants' single scroll/hero.

### Dynamic / animated elements
- Mac: the active pipeline step's `Meter` (0.74), the pulsing accent dot (`st-pulse 1.4s`), and the live-preview wireframe `HeroModel` (its orbit/sheen). In a faithful build the meters/ETA/log would advance over time; the static design captures a single frame at 74% dense reconstruction.
- Phone/Pad: `HandoffArc` beam fill (progress 0.58–0.62) and the streaming pill percentage.

---

## Implementation notes for SwiftUI
- **`HandoffArc` is the signature visual.** Implement with a quadratic `Path` (`addQuadCurve(to:control:)`) for the dotted guide, and place dots by evaluating the quadratic Bézier `B(t) = (1−t)²P0 + 2(1−t)t·C + t²P1` at `t = i/(dots−1)`. Animate by binding `progress` and crossfading dot radius (1.6↔2.6) + color (`text3`↔`accent`) — drive it from the real stream % when wiring to MultipeerConnectivity.
- **Mac 84px left toolbar inset** is mandatory on every Mac screen here (compute/viewer/export/settings share the exact `padding: '0 18px 0 84px'`, `height 52`, `background T.card2`, `borderBottom 0.5px T.line`). Reuse one toolbar container.
- **Pipeline stepper**: the node+connector gutter is a `VStack` per row with the connector as a thin capsule between nodes; only the active row shows a `Meter`. Beware the `&amp;` HTML entity in stage 6 and the `Optimize & export tiers` label — decode to `&`.
- **Stat color tuples** in `COMPUTE_OPTIONS` are *functions* (`() => T.good`) evaluated lazily so dark/light tokens resolve at render — in SwiftUI just resolve the token at body evaluation.
- **Option card order differs by device** (Phone: mac, local; Pad: local, mac) — don't hard-code one order.
- The CTA ternary `go(sel === 'mac' ? 'viewer' : 'viewer')` always routes to `viewer`; only the icon/label change. Keep that behavior.
- Three `Stage`+`HeroModel` material modes appear: default (`pbr`) on the source devices, `wire` on the receiving Mac / live preview. Match the wire material to "still computing" states.
- Telemetry `Meter` values are 0–1 fractions; readings are independent display strings (e.g. memory shows `22 / 48 GB` while the meter is 0.46).
