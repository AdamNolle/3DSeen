# Spec — Library / Home (`library.jsx`)

Source: `studio/screens/library.jsx`. Screen key `'library'` (app home). Variants present: **Phone** (`PhoneLibrary`), **Pad** (`PadLibrary`), **Mac** (`MacLibrary`) + shared `LibrarySidebar`, `Filters`, `Featured`.
Exports: `PhoneLibrary, PadLibrary, MacLibrary, LibrarySidebar, Filters`.

> ⚠️ **Fidelity caveat.** This file was delivered through a redundancy-compressing proxy. The full structural skeleton (layout, style objects, literal copy, numbers) is **verbatim**, but 26 inner JSX spans (`{{HEADROOM_TAG_0..25}}`) could not be retrieved and are **reconstructed by inference**. Each reconstruction below is tagged **[HIGH] / [MED] / [LOW]**. See `docs/design-ref/screens/library.jsx` (RECONSTRUCTION APPENDIX) for the exact marker map. `mode.jsx`/`briefing.jsx` are fully verbatim.

Navigation: New Scan → `go('mode')`; any scan/thumb → `go('viewer')`; settings gear (phone) → `go('settings')`; Mac "Open" → `go('viewer')`.

---

## Shared data (verbatim)

### `Filters({ active='All', onPick })`
`counts = { All: 42, Object: 28, Space: 9, Landscape: 5 }`. Row `flex; gap:8`. One pill button per key:
- `padding:'7px 13px'; borderRadius:999; border:none; cursor:pointer`
- active (`k===active`): bg `T.ink`, color `T.bg`, boxShadow `none`.
- inactive: bg `T.fieldFill`, color `T.text2`, boxShadow `inset 0 0 0 0.5px {T.line}`.
- `fontFamily:T.sf; fontSize:13; fontWeight:600; letterSpacing:-0.1; flex; gap:6; align center`.
- content: `{k}` + mono count span (`.st-num`, fontSize **11**, opacity **0.6**).
- onClick: `onPick && onPick(k)`.

### `LibrarySidebar({ go, w=248, mac=false })` (used by Pad & Mac)
Column `width:w; flexShrink:0; flex column; gap:6; height:100%`.
- **Logo header** (only when `!mac`) [`!mac` branch]: `flex; align center; gap:10; padding:'4px 8px 12px'`. Accent square `30×30; borderRadius:9; background:T.accent; grid center` containing **[MED] `<Ic name="scan" s={18} c={T.onAccent} sw={2} />`**. Text: `3DSeen` (fontSize **15**, weight **700**, letterSpacing **-0.3**, color `T.ink`) + mono `v2.4 · STUDIO` (`fontFamily:T.mono`, fontSize **9.5**, color `T.text3`).
- **Nav list** `nav` = 4 rows:
  | icon (`i`) | title (`t`) | count (`c`) | active (`on`) |
  |---|---|---|---|
  | `grid` | `All Scans` | 42 | **true** |
  | `cube` | `Objects` | 28 | |
  | `room` | `Spaces` | 9 | |
  | `landscape` | `Landscapes` | 5 | |
  Each: `<button>` `flex; align center; gap:11; padding:'9px 12px'; borderRadius:12; border:none; textAlign:left`; bg `T.fieldFillHi` if `on` else `transparent`. Leading **[MED] `<Ic name={r.i} s={17} c={r.on ? T.ink : T.text2} />`**; title span `flex:1; fontSize:14; fontWeight: r.on?650:500; color: r.on?T.ink:T.text2`; trailing mono count `fontSize:11; color:T.text3`.
- **[LOW] `{{TAG_10}}`** divider/spacer after nav (likely `<Rule />` w/ ~8px margin).
- **Collections** `<Label style={{padding:'0 12px 4px'}}>Collections</Label>` then 4 rows `collections`:
  | title | count | dot color |
  |---|---|---|
  | `Museum Loan` | 12 | `#9B8769` |
  | `Renovation 5B` | 8 | `#C58F4B` |
  | `Field · Granite` | 5 | `#4C5A60` |
  | `Cassette Series` | 9 | `#566C70` |
  Each: `<button>` `flex; align center; gap:11; padding:'7px 12px'; borderRadius:12; transparent; textAlign:left`. Leading `9×9` dot (`borderRadius:3; background:dot`); title span `flex:1; fontSize:13.5; fontWeight:500; color:T.text2`; trailing mono count `fontSize:10.5; color:T.text4`.
- Spacer `<div style={{flex:1}}/>` then **[LOW] `{{TAG_11}}`** footer (storage meter or settings/profile button — exact markup unknown).

### `Featured({ scan, go, big=false })` — **[LOW] body unknown (`{{TAG_0}}`)**
The hero scan card rendering `SCANS[0]`. From usage it takes `scan`, `go`, optional `big` (Pad/Mac use big). Inferred role: large Stage + 3D render (HeroModel/ScanThumb) with the scan's name/mode/stats and an open affordance; `big` ⇒ wider horizontal layout. **Markup not recoverable — design around SCANS[0] fields (see ScanThumb fields below).**

### `ScanThumb` (from `render.jsx`, not in this file)
Grid cells render `<ScanThumb scan={s} />` (confirmed). Each grid item is wrapped `<div key={s.id} onClick={() => go('viewer')}>`. ScanThumb consumes `scan.id/name/mode/tone/tier/mb` etc. (per render.jsx).

---

## PHONE — `PhoneLibrary`  (state: `filter`, default `'All'`)

Root `absolute; inset:0; background:T.bg`. **[HIGH] `<StatusBar />`** pinned.
Scroll body `.st-scroll`: `absolute; inset:0; top:54; bottom:0; overflow:auto`; inner `padding:'8px 20px 120px'`.

Top→bottom inside scroll:
1. **Header row** (`flex, space-between, center; paddingTop:4`):
   - `<Label>3DSeen · 42 scans</Label>`
   - Right group (`flex; gap:8`): settings button `36×36` circle (`borderRadius:999; border:none; background:T.fieldFill; grid center`), onClick `go('settings')`, icon **[MED] `<Ic name="settings" s={18} c={T.text2} />`**.
2. **Title** `Library` — fontSize **36**, weight **720**, letterSpacing **-1.2**, lineHeight **1**, color `T.ink`, marginTop 6.
3. **Subtitle** `11.4 GB on device · 2 syncing to iCloud` — fontSize **13.5**, color `T.text2`, marginTop 6.
4. **Search field** (`marginTop:16; flex; align center; gap:10; height:44; padding:'0 14px'; borderRadius:14; background:T.fieldFill; boxShadow:inset 0 0 0 0.5px {T.line}`): leading **[MED] `<Ic name="search" s={17} c={T.text3} />`** + placeholder `Search scans, tags, materials` (fontSize **14.5**, color `T.text3`). (Non-interactive mock.)
5. **Featured** (`marginTop:16`): **[HIGH] `<Featured scan={SCANS[0]} go={go} />`**.
6. **Filters** (`marginTop:18; marginBottom:12`): **[HIGH] `<Filters active={filter} onPick={setFilter} />`**.
7. **Grid** (`gridTemplateColumns:'1fr 1fr'; gap:12`): `SCANS.slice(1,7)` (6 items) → each `<div onClick={go('viewer')}>` **[HIGH] `<ScanThumb scan={s} />`**.
8. **Floating new-scan dock** (pinned, outside scroll): `absolute; bottom:28; left:0; right:0; flex; justify center; zIndex:20` → **[MED] `{{TAG_7}}`** = accent "New Scan" pill, e.g. `<Button kind="accent" size="lg" onClick={() => go('mode')}><Ic name="scan" s={18} c={T.onAccent} sw={2}/> New Scan</Button>` (possibly wrapped in `<Glass>`).

---

## PAD — `PadLibrary`

Root `absolute; inset:0; background:T.bg`. **[HIGH] `<PadStatusBar />`** pinned. Body: `absolute; inset:0; top:30; display:flex; padding:22; gap:22`.
- **Left: sidebar** **[HIGH] `<LibrarySidebar go={go} />`** (default `w=248`, shows logo header).
- **Right: main** `.st-scroll` `flex:1; overflow:auto; minWidth:0`:
  1. **Search row** (`flex; align center; gap:12`):
     - Search field `flex:1; height:46; padding:'0 14px'; borderRadius:14; background:T.fieldFill; boxShadow:inset 0 0 0 0.5px {T.line}`; leading **[MED] `<Ic name="search" s={18} c={T.text3} />`** + placeholder `Search scans, tags, materials…` (fontSize **14.5**, color `T.text3`).
     - `<Button kind="accent" onClick={() => go('mode')}>` leading **[HIGH] `<Ic name="scan" s={17} c={T.onAccent} sw={2} />`** + ` New Scan`.
  2. **Featured** (`marginTop:18`): **[HIGH] `<Featured scan={SCANS[0]} go={go} big />`**.
  3. **Recent header** (`flex; align baseline; space-between; marginTop:24; marginBottom:12`): title `Recent` (fontSize **20**, weight **700**, letterSpacing **-0.4**, color `T.ink`) + **[MED] `{{TAG_17}}`** right affordance (sampled `<Filters />`).
  4. **Recent grid** (`gridTemplateColumns:'repeat(5,1fr)'; gap:14`): `SCANS.slice(1)` (all but featured) → `<div onClick={go('viewer')}>` **[HIGH] `<ScanThumb scan={s} />`**.

---

## MAC — `MacLibrary`

Root `absolute; inset:0; background:T.bg; display:flex`. Two regions side-by-side:

### Left sidebar (pinned)
`width:264; flexShrink:0; background:T.card2; borderRight:0.5px solid {T.line}; padding:'52px 16px 18px'; flex column` → **[HIGH] `<LibrarySidebar go={go} mac />`** (mac=true ⇒ **no** logo header; the 52px top padding clears the macOS traffic-light/title area).

### Main (`flex:1; flex column; minWidth:0`)
1. **Toolbar** `height:52; flexShrink:0; borderBottom:0.5px solid {T.line}; flex; align center; gap:14; padding:'0 20px'; background:T.card2`:
   - `<div style={{width:56}} />` (traffic-light gutter).
   - Title `All Scans` (fontSize **15**, weight **700**, letterSpacing **-0.3**, color `T.ink`).
   - **[LOW] `{{TAG_20}}`** toolbar accessory (count chip / breadcrumb / Filters).
   - Spacer `<div style={{flex:1}}/>`.
   - Search box `flex; align center; gap:8; height:32; padding:'0 12px'; borderRadius:9; background:T.fieldFill; width:260; boxShadow:inset 0 0 0 0.5px {T.line}`: leading **[MED] `<Ic name="search" s={14} c={T.text3} />`** + `Search` (fontSize **13**, color `T.text3`).
   - `<Segmented size="sm" options={[{value:'grid',label:'◧'},{value:'list',label:'☰'}]} value="grid" onChange={()=>{}} />` (grid/list toggle, grid selected).
   - `<Button kind="accent" size="sm" onClick={() => go('viewer')}>` leading **[LOW] `<Ic name="open" .../>`** + ` Open`.
2. **Content** `.st-scroll` `flex:1; overflow:auto; padding:24`:
   - **Hero band** **[MED] `{{TAG_23}}`** = `<Featured scan={SCANS[0]} go={go} big />` (inferred).
   - **Recent header** (`flex; align baseline; space-between; marginTop:26; marginBottom:14`): `Recent` (fontSize **18**, weight **700**, letterSpacing **-0.3**) + **[MED] `{{TAG_24}}`** affordance.
   - **Recent grid** (`gridTemplateColumns:'repeat(6,1fr)'; gap:16`): `SCANS.slice(1)` → `<div onClick={go('viewer')}>` **[HIGH] `<ScanThumb scan={s} />`**.

---

## Device differences
- **Phone**: single scroll column, 54pt status bar, 36px title, big search field, Featured (small), Filters chips, 2-col grid of 6 (`SCANS.slice(1,7)`), floating centered "New Scan" dock. Settings gear in header.
- **Pad**: 30pt status bar, 248px `LibrarySidebar` (with logo) + scrolling main, inline search + "New Scan" accent button, Featured `big`, "Recent" 5-col grid of all scans.
- **Mac**: native chrome — 264px sidebar (`T.card2`, right border, `mac` mode = no logo, 52px top inset), 52px toolbar (traffic-light gutter, title, search 260px, grid/list `Segmented`, "Open" button), scrolling content with Featured hero band + 6-col "Recent" grid. Uses `T.card2` surfaces and hairline borders rather than the iOS field fills.

## Grid item counts
- Phone grid: `SCANS.slice(1,7)` = 6 thumbs. Pad/Mac grids: `SCANS.slice(1)` = all scans except the featured `SCANS[0]`.

## Animated / dynamic
- No explicit keyframes in this file. Featured/ScanThumb/HeroModel may animate internally (orbit/sheen). Filter pills swap bg on selection (`active` → `T.ink`/`T.bg`).

## Implementation notes for SwiftUI
- **Reconstructed regions** (verify against the live design before pixel-locking): `Featured` card body (TAG_0), Phone floating dock (TAG_7), sidebar footer (TAG_11), Mac toolbar accessory (TAG_20) and "Open" icon (TAG_22), and the Recent-header right affordances (TAG_17/24). Everything outside the markers is exact.
- `LibrarySidebar` is one component with a `mac` flag — on Mac it drops the logo row and the host provides the 52px top inset + `T.card2` background; on Pad it shows the logo and sits on `T.bg`. Build one reusable sidebar with a `mac` style branch.
- Mono font (`T.mono`, `.st-num`) is used for all counts and the `v2.4 · STUDIO` caption; everything else `T.sf`.
- Filter pill active state inverts to `T.ink` bg / `T.bg` text (a "selected dark chip") — distinct from the iOS-style inactive `fieldFill` chip with a hairline inset shadow.
- Search fields are non-functional placeholders (static `<span>` text, no input) — render as tappable rows.
- The Phone "New Scan" dock floats above the scroll (`zIndex:20`, `bottom:28`), centered; the scroll body reserves space with `paddingBottom:120`.
- `Segmented` glyph options use literal characters `◧` (grid) and `☰` (list).
