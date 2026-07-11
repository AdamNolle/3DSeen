# Spec — Capture Mode Picker (`mode.jsx`)

Source: `studio/screens/mode.jsx` (verbatim). Screen key `'mode'`. Step 1 of 4 in the New-Scan flow. Variants present: **Phone** (`PhoneModePicker`), **Pad** (`PadModePicker`). **No Mac variant.**
Navigation in flow: `library → mode → briefing → quality(Detail) → capture`.

Shared exports: `MODES`, `StepTabs`, `PhoneModePicker`, `PadModePicker`.

---

## Data — `MODES` (4 items, order matters: Auto is index 0 / featured)

| idx | id | name | icon | tag | sub | specs (3 chips) | tint (literal hex) |
|---|---|---|---|---|---|---|---|
| 0 | `auto` | **Auto-Pilot** | `sparkle` | `CoreML scene analysis` | `A vision model reads the live feed and selects the optimal mode for you.` | `Adaptive`, `Recommended`, `No setup` | `#2D68F0` |
| 1 | `object` | **Object** | `cube` | `Photogrammetry · ObjectCapture` | `Hi-fidelity model of a single object. RealityKit-native, LiDAR-optional.` | `LiDAR optional`, `8K textures`, `4–10 min` | `#5B7E84` |
| 2 | `space` | **Space** | `room` | `RoomPlan · Parametric` | `Structural blocks of rooms, walls, openings, furniture. LiDAR-required.` | `LiDAR required`, `USDZ + walls`, `2–5 min` | `#7A6244` |
| 3 | `landscape` | **Landscape** | `landscape` | `ARKit VIO · GPS anchored` | `Outdoor scenes where LiDAR is blinded by sun. Visual-inertial odometry.` | `No LiDAR`, `GPS anchored`, `6–20 min` | `#4C5A60` |

Selection state: `sel` (React state), defaults `'auto'`. Each variant owns its own `sel`.

---

## Component — `ModeTile({ mode, selected, onPick, big=false })`

Root: `<button className="st-tap">` full width, `onClick=() => onPick(mode.id)`.
- `position: relative; overflow: hidden; textAlign: left; cursor: pointer; width: 100%`
- `borderRadius`: **22** if `big` else **18**
- `padding`: **20** if big else **15**
- `background`: `T.accentSoft` if selected else `T.card`
- `border`: `0.5px solid` → `T.accentLine` if selected else `T.line`
- `boxShadow`: selected → `0 0 0 1px {T.accentLine}, {T.cardShadow}` ; else `T.cardShadow`
- `display: flex; flexDirection: column; height:` `100%` if big else `auto`

Top row (`flex, space-between, center`):
- Icon chip: square `48` (big) / `40`, `borderRadius` `14`(big)/`12`, `display:grid; placeItems:center`.
  - bg: `T.accent` if selected else `T.fieldFill`
  - boxShadow: selected → `none` ; else `inset 0 0 0 0.5px {T.line}`
  - Icon: `<Ic name={mode.icon} s={big?24:20} c={selected ? T.onAccent : mode.tint} />`
- If `selected`: `<Chip tone="accent" style={{fontSize:9}}>SELECTED</Chip>` (right-aligned).

Body:
- Title `{mode.name}`: fontSize `22`(big)/`17`, weight **700**, letterSpacing **-0.4**, color `T.ink`, marginTop `14`(big)/`10`.
- `<Label color={selected ? T.accentText : T.text3} style={{marginTop:4}}>{mode.tag}</Label>` (Label = mono overline).
- If `big`: subtitle `{mode.sub}` — fontSize **13**, color `T.text2`, marginTop **8**, lineHeight **1.4**.
- If `big`: spec chips row — `flex; gap:6; marginTop:auto; paddingTop:14; flexWrap:wrap`; each `<Chip tone="neutral" style={{fontSize:11}}>{spec}</Chip>`.

Note: non-big tiles show **only** icon row + title + tag (no sub, no spec chips).

---

## Component — `StepTabs({ active })`  (Pad only)

`steps = ['Mode','Briefing','Detail','Capture']`. Container `flex; gap:6`.
Each step pill: `flex; align center; gap:7; padding:'7px 13px'; borderRadius:10`.
- `on = i===active`, `done = i<active`.
- bg: `T.fieldFillHi` if on else `transparent`; color `T.ink` if on else `T.text3`; fontSize **13**, weight **650** if on else **500**.
- Leading number badge: `16×16` circle (`borderRadius:99`), `display:grid; placeItems:center`, `fontFamily:T.mono`, fontSize **9**, weight **700**.
  - bg: `done` → `T.good`, `on` → `T.accent`, else `T.fieldFillHi`.
  - color: `(done||on) ? '#fff' : T.text3`.
  - content: `'✓'` if done else `i+1`.

---

## PHONE — `PhoneModePicker`

Layout top→bottom (root `position:absolute; inset:0; background:T.bg`):
1. `<StatusBar />` (pinned, 54pt implied — scroll starts at `top:54`).
2. **Scroll body** `.st-scroll`: `absolute; inset:0; top:54; overflow:auto; padding:'8px 20px 110px'`.
   - **Nav row** (`flex, space-between, center`):
     - Back button: `36×36` circle (`borderRadius:999`), bg `T.fieldFill`, `<Ic name="back" s={17} c={T.text2}/>`, onClick `go('library')`.
     - `<Chip tone="neutral">Step 1 of 4</Chip>` (center).
     - Close button: `36×36` circle, bg `T.fieldFill`, `<Ic name="close" s={16} c={T.text2}/>`, onClick `go('library')`.
   - **Title block** (`marginTop:18`):
     - `<Label>Choose capture</Label>`
     - H1 (`marginTop:6`): fontSize **30**, weight **720**, letterSpacing **-1**, lineHeight **1.05**, color `T.ink` — copy: `What are you<br/>scanning today?` (hard line break).
     - Sub (`marginTop:8`): fontSize **13.5**, color `T.text2` — `Auto-Pilot will pick for you — or choose a mode.`
   - **Featured tile** (`marginTop:18`): `<ModeTile mode={MODES[0]} big selected={sel==='auto'} onPick={setSel} />` (full-width big Auto-Pilot tile).
   - **2×2 grid** (`gridTemplateColumns:'1fr 1fr'; gap:12; marginTop:12`): `MODES.slice(1)` → non-big `ModeTile`s (Object, Space, Landscape — only 3, so last cell empty).
3. **Pinned footer dock**: `absolute; bottom:28; left:20; right:20`.
   - `<Button kind="accent" full size="lg" onClick={() => go('briefing')}>` with leading `<Ic name={selectedMode.icon} s={18} c={T.onAccent}/>` and label:
     - if `sel==='auto'` → `Start Auto-Pilot`
     - else → `` Continue · {selectedModeName} `` (e.g. `Continue · Object`).

---

## PAD — `PadModePicker`

Root `absolute; inset:0; background:T.bg`. `<PadStatusBar />` pinned. Content container: `absolute; inset:0; top:30; display:flex; flexDirection:column; padding:24`. **Single non-scrolling column** (uses flex/`minHeight:0` to fill).

Top→bottom:
1. **Header row** (`flex, space-between, center`):
   - Left group (`flex; gap:12`): Back button `38×38` circle bg `T.fieldFill` `<Ic name="back" s={17} c={T.text2}/>` → `go('library')`; then a title stack: `<Label>New Scan · Step 1 of 4</Label>` + `Choose capture mode` (fontSize **17**, weight **700**, letterSpacing **-0.3**, marginTop 2).
   - Center: `<StepTabs active={0} />`.
   - Right: Close button `38×38` circle `<Ic name="close" s={16} c={T.text2}/>` → `go('library')`.
2. **Hero row** (`flex; alignItems:flex-end; gap:20; marginTop:28; marginBottom:22`):
   - Left (`flex:1`):
     - `<Label color={T.accentText}>3DSeen · Capture engine</Label>`
     - H1 (`marginTop:8`): fontSize **48**, weight **730**, letterSpacing **-2**, lineHeight **1**, color `T.ink` — `What are you scanning?`
     - Body (`marginTop:12; maxWidth:560; lineHeight:1.45`): fontSize **15**, color `T.text2` — `Auto-Pilot uses a CoreML vision model to read the scene and pick the optimal capture mode. Or pin a specific mode for full manual control.`
   - Right: **Live scene card** — `<Card radius={18}>` `padding:14; width:280; flex; gap:12; align center`:
     - `56×56` rounded (`borderRadius:14; overflow:hidden`) `<Stage radius={14}><HeroModel w={56} h={56}/></Stage>`.
     - Text stack: `<Label>Live scene</Label>`; `Object · table-top` (fontSize **14**, weight **650**, marginTop 3); mono caption `conf 92% · 1840 lux` (`fontFamily:T.mono`, fontSize **10.5**, color `T.text3`, marginTop 2).
3. **Mode grid** (`gridTemplateColumns:'1.3fr 1fr 1fr 1fr'; gap:14; flex:1; minHeight:0`): **all 4** `MODES` as `big` tiles (Auto wider via 1.3fr).
4. **Footer row** (`flex, space-between, center; marginTop:20`):
   - Left status group (`flex; gap:28`), three `Label + value` pairs:
     - `Device` / `iPad Pro M4 · LiDAR`
     - `Thermal` / `Nominal · 31°C`
     - `Storage` / `244.6 GB free`
     - value style: fontSize **13.5**, weight **600**, color `T.ink`, marginTop 3.
   - Right: `<Button kind="accent" size="lg" onClick={() => go('briefing')}>` leading `<Ic name={selectedMode.icon} s={18} c={T.onAccent}/>` + ``Continue with {selectedModeName}`` (always this form — no special Auto label on Pad).

---

## Device differences (Pad vs Phone)
- Phone: scrollable, 54pt status bar, big Auto tile + 2×2 grid of the other 3, pinned bottom CTA; primary CTA text branches on Auto.
- Pad: 30pt status bar, single fixed column, `StepTabs` stepper, marketing hero with live-scene preview card (Stage+HeroModel), all 4 modes as big tiles in one 4-col row (Auto column 1.3×), device/thermal/storage status footer, CTA always `Continue with {name}`.

## Interactions
- `onPick(id)` sets local `sel`. Back & Close both → `go('library')`. Primary CTA → `go('briefing')`.

## Animated / dynamic
- None intrinsic to this screen (HeroModel may animate internally). Selection drives tile bg/border/shadow + `SELECTED` chip + icon-chip fill swap.

## Implementation notes for SwiftUI
- `selectedMode.icon` is computed via `MODES.find(id===sel)` for the CTA icon — keep selection as an enum and map to SF Symbol/asset.
- `letterSpacing` values are in px on ~ default 16px context; convert to tracking carefully (e.g. -2 on a 48pt title is large negative tracking).
- Phone big-tile + 2×2 grid: the 3 remaining modes leave the 4th grid cell empty — do **not** stretch.
- Pad grid uses fractional `1.3fr 1fr 1fr 1fr`; replicate with a GeometryReader/Grid weighting, and tiles must fill height (`big` tiles use `marginTop:auto` to push spec chips to the bottom).
- Number badges in `StepTabs` and mono captions use the **mono** font (`T.mono`); everything else uses `T.sf`.
- `Chip tone="accent"` SELECTED badge is fontSize 9 — very small uppercase.
