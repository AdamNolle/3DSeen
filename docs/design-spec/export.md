# Export & Share — SwiftUI implementation spec

Source: `studio/screens/export.jsx` (fully verbatim). Exports `PhoneExport`, `PadExport`, `MacExport`. Purpose: configure and run a file export with a 3-state flow **config → progress → done**. iPhone uses a bottom sheet, iPad a centered modal, Mac a full workspace pane. Depends on the shared `EXPORT_FORMATS` data (from `studio/data.jsx`).

Tokens: accent `#2D68F0`/`#5E9BFF`, `T.mono` for all `st-num` text.

---

## Shared state machine — `useExportFlow()`
- `stage`: `'config' | 'progress' | 'done'` (initial `config`).
- `fmt`: selected format id, initial **`'usdz'`**.
- `dest`: selected destination id, initial **`'air'`**.
- `opts`: object of per-option booleans, initialized from `EXPORT_OPTIONS` defaults.
- `pct`: 0–100 progress.
- `start()`: sets `stage='progress'`, `pct=0`, then a `setInterval` every **180 ms** increments `pct` by `random()*9 + 3` (≈3–12 per tick). On reaching ≥100 it clamps to 100, clears the timer, and after **360 ms** sets `stage='done'`.
- `reset()`: clears timer, back to `config`, `pct=0`.
- `format` = the `EXPORT_FORMATS` entry whose `id === fmt`.
- SwiftUI: model as an `@Observable`/`ObservableObject` with a `Timer`; `pct` animates a `Ring`. The random step makes a slightly irregular fill — acceptable to approximate.

## Data tables

### `DESTINATIONS` (the "Send to" row — 4 items, order matters)
1. `air` — **"AirDrop"** — icon `airdrop`.
2. `mac` — **"Adam's MBP"** — icon `laptop`.
3. `icloud` — **"iCloud"** — icon `cloud`.
4. `files` — **"Files"** — icon `folder`.

### `EXPORT_OPTIONS` (toggle rows — 4 items, default on/off)
1. `measure` — **"Include measurements (3 pins)"** — default **ON**.
2. `bake` — **"Bake materials to 2K"** — default **OFF**.
3. `scale` — **"Scale to scene · 1.0×"** — default **ON**.
4. `color` — **"Color-managed (Display P3)"** — default **ON**.

### `EXPORT_FORMATS` (from data.jsx — the format list; usdz/usd/glb/obj/fbx/ply)
Each row exposes `name` (short badge, e.g. "USDZ"), `ext` (e.g. ".usdz"), `desc`, `size` (e.g. "184 MB"), and one has `best: true`. iPhone shows only the **first 3**; iPad and Mac show **all 6**. (Pull exact name/ext/desc/size strings from `data.jsx`.)

---

## Shared sub-components

### `FormatRow` — a selectable format row
- Full-width button, row, gap 12, padding 12, radius 14, `textAlign left`.
- Background: selected → `T.accentSoft`, else `T.fieldFill`. Box shadow: selected `inset 0 0 0 1px T.accentLine`, else `inset 0 0 0 0.5px T.line`.
- Left badge tile `40×40` radius 10: background selected `T.accent` else `T.card` (unselected has `inset 0 0 0 0.5px T.line`); contains `f.name` text at `11.5px / weight 800 / letterSpacing -0.2`, color selected `T.onAccent` else `T.text2`.
- Middle column: title row = `f.ext` (`14px / 650 / T.ink / mono`) + when `f.best` an accent `Chip` **"BEST"** (`fontSize 9, padding 2px 6px`); below `f.desc` at `11.5px / T.text3 / marginTop 2`.
- Right: `f.size` mono (`12px / T.text2`).
- Far right: a `20×20` round check well — selected fills `T.accent` with `Ic check s=13 c=T.onAccent sw=2.6`; unselected is transparent with `inset 0 0 0 1.5px T.line`.
- Tap → `onPick(f.id)`.

### `DestRow` — destination picker (horizontal, 4 equal cells)
- Row, gap 12; each item is a column button (`flex 1`, gap 8):
  - `56×56` round-rect (radius 18): selected background `T.accent` with shadow `0 4px 14px T.accentSoft`; unselected `T.fieldFill` with `inset 0 0 0 0.5px T.line`. Icon `Ic name={d.i} s=24` color selected `T.onAccent` else `T.text2`.
  - Label `d.l` at `11.5px`, weight selected 650 else 500, color selected `T.ink` else `T.text2`.
- Tap → `onChange(d.id)`.

### `ProgressView` (`big` for Pad/Mac)
- Centered column (gap `big ? 22 : 16`, padding `big ? '20px 0' : '8px 0'`).
- `Ring value={pct/100} size={big ? 132 : 104} stroke={big ? 9 : 8} label={round(pct)} sub="%"` (progress ring with the integer percent in the center, "%" sub-label).
- Title **"Exporting {format.name}…"** at `big ? 20 : 16` px / weight 700 / letterSpacing -0.3 / T.ink.
- Sub line (mono, `13px / T.text2 / marginTop 4`): phase text + ` · {format.size}`. Phase text is `pct<40 ? "Triangulating mesh" : pct<75 ? "Packing 4K textures" : "Writing "+format.ext`.
- Neutral `Chip`: `Ic name={dest.i} s=14 c=T.text2` + **"to {dest.l}"**.

### `DoneView` (`big` variant; uses entry anim `st-rise-in`)
- Centered column (gap `big ? 20 : 14`).
- Success badge: outer circle `big ? 84 : 68` in `T.goodSoft`, inner circle `big ? 56 : 46` in `T.good` with `Ic check s={big ? 30 : 24} c=#fff sw=2.6`.
- Title **"Export complete"** (`big ? 22 : 18` px / weight 720 / letterSpacing -0.4 / T.ink).
- Sub (mono, `13.5px / T.text2 / marginTop 5`): **"Celestial Bust{format.ext} · {format.size} · sent to {dest.l}"**.
- Two buttons (gap 8, marginTop 4): `secondary` **"Export again"** (`Ic refresh s=15 c=T.ink`) → `onAgain` (=`reset`); `accent` **"Done"** (`Ic check s=15 c=T.onAccent`) → `go('library')`.

### `ModelBadge` (default `size=50`)
- Square radius 12, `overflow hidden`, `inset 0 0 0 0.5px T.line`; contains `Stage(radius 12)` + `HeroModel size×size`.

---

## iPhone — `PhoneExport` (bottom sheet over a dimmed stage)

### Layout hierarchy (back → front)
1. **Backdrop**: full-bleed `Stage` + `HeroModel w=402 h=500`.
2. **Dim overlay**: absolute inset 0, background `rgba(0,0,0,0.45)` (dark mode) / `rgba(20,20,30,0.28)` (light).
3. **`StatusBar`** (pinned).
4. **Sheet** (`st-sheet-in` slide-up): pinned to bottom (`left/right/bottom 0`). A `Glass radius=30` with bottom corners squared (`borderBottom*Radius 0`), padding `12px 18px 34px`.
   - Grabber: `38×5` pill, radius 99, `T.lineStrong`, centered, margin `0 auto 14px`.
   - **stage === 'config'** content:
     - Header row (gap 12, center): `ModelBadge` (50); text column with title **"Export Celestial Bust"** (`17px / 700 / letterSpacing -0.3`) + mono meta **"FULL · 4.2M tris · 184 MB"** (`11px / T.text3`); a `32×32` round close button (`T.fieldFill`, `Ic close s=15 c=T.text2`) → `go('viewer')`.
     - `Label` **"Send to"** (marginTop 18, marginBottom 10) → `DestRow`.
     - `Label` **"Format"** (marginTop 18, marginBottom 10) → column (gap 8) of `FormatRow` for **first 3** `EXPORT_FORMATS`.
     - Toggle rows (gap 2, marginTop 14): **first 2** `EXPORT_OPTIONS` only. Each: label `13.5px / T.ink / 500` + `Toggle`.
     - CTA (marginTop 16): `Button kind="accent" full size="lg"` `Ic export s=17 c=T.onAccent` + **"Export {format.name} · {format.size}"** → `start()`.
   - **stage === 'progress'** → `ProgressView` (small).
   - **stage === 'done'** → `DoneView` (small).

### Notes
- iPhone deliberately trims to 3 formats + 2 options to fit the sheet; the full sets live on iPad/Mac.
- Close button routes back to `viewer`; CTA stays inside the sheet (swaps content) until Done → `library`.

---

## iPad — `PadExport` (centered modal over dimmed stage)

### Layout
1. Backdrop `Stage` + `HeroModel w=1194 h=834`.
2. Dim overlay `rgba(0,0,0,0.5)` / `rgba(20,20,30,0.32)`.
3. `PadStatusBar tone="light"`.
4. Centered modal container (grid place-center, padding 40): `Glass radius=26` (`st-modal-in`), `width 880` (maxWidth 100%), `padding 0`, `overflow hidden`.
   - **Header** (row, gap 12, padding `16px 22px`, `borderBottom 0.5px T.line`): `ModelBadge size=44`; title **"Export & Share"** (`17px / 700 / -0.3`) + mono **"CELESTIAL BUST · FULL · 184 MB"** (`11px / T.text3`); `34×34` round close (`Ic close s=16 c=T.text2`) → `go('viewer')`.
   - **stage === 'config'** → 2-column grid (`1fr 1fr`, minHeight 420):
     - **Left column** (padding 22, `borderRight 0.5px T.line`, flex column):
       - Preview pane (`flex 1`, radius 18, `overflow hidden`, minHeight 200): `Stage(18)` + `HeroModel 400×300`; top-right accent `Chip` (`Ic scan s=13 c=T.accentText` + **"AR Quick Look ready"**).
       - Stats grid (`repeat(4,1fr)`, gap 12, marginTop 16): `Stat Format {format.name}` (color `T.accentText`), `Stat Size {format.size.split(' ')[0]} unit="MB"`, `Stat Tris 4.2M`, `Stat Tex 4K` — all `size=sm`.
       - `Label` **"Send to"** → `DestRow`.
     - **Right column** (scroll, padding 22, flex column):
       - `Label` **"Format"** → column (gap 8) of `FormatRow` for **all 6** formats.
       - `Label` **"Options"** (marginTop 18, marginBottom 6) → all 4 `EXPORT_OPTIONS` rows; each row padding `9px 2px` with a `borderTop 0.5px T.line` for every row except the first (`measure`). Label `13.5px / T.ink / 500` + `Toggle`.
       - Spacer, then CTA `Button accent full size=lg` (`Ic export s=17 c=T.onAccent` + **"Export {format.name} · {format.size}"**) → `start()`.
   - **stage === 'progress' / 'done'** → a `minHeight 420` grid place-center holding `ProgressView big` or `DoneView big`.

### Device differences vs iPhone
- Two-pane modal: left = live preview + key stats + destinations; right = full format list + all options. Shows all 6 formats and all 4 options (iPhone shows 3/2).
- Progress/done are `big` and centered in the 420-tall modal body.

---

## Mac — `MacExport` (full workspace pane)

### Toolbar (height 52, pinned)
- Background `T.card2`, `borderBottom 0.5px T.line`, padding `0 18px 0 84px` (traffic-light inset).
- Back chip-button (height 30, radius 8, `T.fieldFill`, `Ic back s=15 c=T.text2`, **"Model"**) → `go('viewer')`; vertical `Rule` height 22; title **"Export · Celestial Bust"** (`15px / 700 / -0.3`); spacer; neutral `Chip` (`Ic layers s=13 c=T.text2` + **"6 formats"**).

### Body (flex row)
- **Preview** (`flex 1`, relative, `borderRight 0.5px T.line`):
  - Full-bleed `Stage` + `HeroModel w=620 h=620 material={fmt === 'ply' ? 'wire' : 'pbr'}` (PLY shows wireframe, everything else PBR).
  - Top-left accent `Chip` (`Ic scan s=13 c=T.accentText` + **"AR Quick Look ready"**).
  - Bottom-center `Glass radius=16` (padding `12px 18px`, gap 26): `Stat Format {format.name}` (color `T.accentText`), `Stat Size {format.size.split(' ')[0]} unit="MB"`, `Stat Triangles 4.2M`, `Stat Textures "4K PBR"`, all `size=sm`.
- **Config panel** (width 380, scroll, background `T.card2`, padding 22, flex column):
  - **stage === 'config'**:
    - `Label` **"Format"** → column (gap 8) of `FormatRow` for **all 6** formats.
    - `Label` **"Options"** (marginTop 20, marginBottom 6) → all 4 `EXPORT_OPTIONS` (same borderTop-except-first rule as iPad).
    - `Label` **"Destination"** (marginTop 20, marginBottom 10) → `DestRow`.
    - Spacer; CTA `Button accent full size=lg` (`Ic export s=17 c=T.onAccent` + **"Export {format.name} · {format.size}"**) → `start()`; under it a centered mono path string **"~/Exports/3DSeen/celestial-bust{format.ext}"** (`11px / T.text3 / marginTop 10`).
  - **stage === 'progress'** → `flex 1` grid place-center → `ProgressView big`.
  - **stage === 'done'** → `flex 1` grid place-center → `DoneView big`.

### Device differences
- Mac is a side-by-side workspace (persistent large preview + right config rail), not an overlay. Preview material reacts to the selected format (`ply` → wire). Shows the literal output file path. Destination row sits below options (vs above on iPhone/iPad).

### Dynamic / animated elements
- `Ring` fill during progress (driven by the 180 ms `setInterval`), `st-sheet-in` (iPhone), `st-modal-in` (iPad), `st-rise-in` (DoneView). The hero model orbit/sheen is constant.

---

## Implementation notes for SwiftUI
- **The format list (`FormatRow`) is the trickiest fidelity item.** It is a 4-zone row: square name-badge tile, ext+desc text, mono size, and a radio "check well." Selection drives *five* simultaneous style swaps (row bg, row inset-shadow, badge bg, badge text color, check well fill+icon). Build it as one reusable row that takes `isSelected`; don't approximate with a stock `List` selection style. The badge text is the short `name` (USDZ); the title is the dotted `ext` (.usdz).
- **Variant format/option counts differ**: iPhone = first 3 formats + first 2 options; iPad/Mac = all 6 + all 4. Slice the data accordingly.
- **Option rows' separators**: a `borderTop` appears on every option row *except* the first (`id !== 'measure'`) — i.e. internal dividers only.
- **Progress phase text is percentage-gated** (`<40` / `<75` / else) and the sub-string also appends `format.ext` only in the final phase — keep the three literal phases.
- **`format.size.split(' ')[0]`** extracts the numeric part of e.g. "184 MB" so a separate `unit="MB"` can be shown; replicate by splitting on space.
- **The bottom sheet / centered modal / workspace are three presentations of one flow** — share the config/progress/done subviews; only the chrome (sheet vs modal vs split pane) and the data slice differ.
- **Mac preview material binds to `fmt`** (`ply` → wireframe). Wire this so changing the selected format updates the hero render.
- Reuse the standard Mac toolbar (height 52, `0 18px 0 84px`, `T.card2`, `0.5px T.line` bottom) shared across all Mac screens.
- Dim overlays use mode-conditional rgba — respect dark vs light.
