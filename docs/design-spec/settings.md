# Settings / Profile — SwiftUI implementation spec

Source: `studio/screens/settings.jsx` (fully verbatim). Exports `PhoneSettings`, `PadSettings`, `MacSettings`. Purpose: account header + grouped preference sections + connected-devices list. iPhone = single scroll list; iPad = sidebar (account + section nav + devices) with a detail column; Mac = native preferences window (left sidebar, right detail with toolbar + search).

Tokens: accent `#2D68F0`/`#5E9BFF`; `T.mono` for all `st-num` text.

---

## Shared data

### `SETTINGS` — 4 sections, each `{ sec, icon, rows[] }`
1. **"Capture defaults"** — icon `camera` — rows:
   - **"Default mode"** → value **"Auto-Pilot"** (icon `sparkle`), disclosure row.
   - **"Default detail tier"** → value **"Medium"** (icon `layers`), disclosure row.
   - **"Audio shutter cue"** (icon `bolt`) — **toggle, default ON**.
   - **"Haptic coaching"** (icon `hand`) — **toggle, default ON**.
2. **"Compute & handoff"** — icon `chip` — rows:
   - **"Auto-handoff to Mac when available"** (icon `laptop`) — **toggle, default ON**.
   - **"Thermal protection"** → **"Auto-pause"** (icon `thermal`).
   - **"Background processing"** → **"Allow"** (icon `chip`).
   - **"Color management"** → **"Display P3"** (icon `light`).
3. **"Storage"** — icon `download` — rows:
   - **"Keep Raw archive on device"** → **"Latest 5"** (icon `download`).
   - **"iCloud backup"** (icon `cloud`) — **toggle, default ON**.
   - **"Smart offload"** → **"> 30 days"** (icon `refresh`) — **toggle, default ON** (this row has BOTH a value and `toggle:true`; the renderer shows only the toggle because `toggle !== undefined`).
4. **"Privacy"** — icon `lock` — rows:
   - **"Location in scan metadata"** (icon `pin`) — **toggle, default OFF**.
   - **"On-device AI only"** (icon `sparkle`) — **toggle, default ON**.
   - **"Anonymous improvement"** (icon `info`) — **toggle, default OFF**.

### `DEVICES` — connected devices (2)
1. **"Adam's MBP"** — sub **"Wi-Fi · M4 Max"** — `on: true` (active).
2. **"Studio Mini"** — sub **"Wired · M2"** — `on: false`.

---

## Shared sub-components

### `Avatar` (default `s=54`)
- Round (radius 99) `s×s`, background `radial-gradient(circle at 32% 28%, T.accent, #1B3A8C)`, shadows `inset 0 1px 1px rgba(255,255,255,0.4), 0 2px 8px T.accentSoft`. Centered glyph **"A"** at `fontSize s*0.4 / weight 700 / #fff`.

### `SettingRow`
- Row (gap 12, padding `11px 0`). Holds its own toggle state (`useState(!!row.toggle)`).
- Left icon tile `30×30` radius 9, `T.fieldFill`, `inset 0 0 0 0.5px T.line`, `Ic name={row.i} s=16 c=T.text2`.
- Label `row.l` (flex 1, `14px / weight 500 / T.ink / letterSpacing -0.2`).
- Right accessory:
  - If `row.toggle !== undefined` → a `Toggle` (controlled by local state).
  - else → value text (`13.5px / T.text2`) + `Ic chev s=14 c=T.text4` (disclosure chevron).

### `Section`
- `Card radius=20`, padding `4px 16px`. Renders each row as `SettingRow` separated by a `Rule` between rows (no rule after the last).

---

## iPhone — `PhoneSettings`

Single scroll on `T.bg`.

### Layout (top → bottom)
1. **`StatusBar`** (pinned).
2. **Scroll body** (`st-scroll`): absolute inset 0, `top 54`, padding `8px 20px 40px`.
   1. **Nav row** (space-between): back `36×36` round (`T.fieldFill`, `Ic back s=17 c=T.text2`) → `go('library')`; neutral `Chip` **"Settings"**; right `36×36` round info button (`Ic info s=16 c=T.text2`, no action).
   2. **Profile card** (`Card radius=24`, padding 18, marginTop 16, row gap 14): `Avatar` (54); name **"Adam Nolle"** (`18px / 720 / -0.4 / T.ink`) + mono **"3DSeen STUDIO · v2.4.1"** (`11px / T.text3`); accent `Chip` **"PRO"** (`fontSize 10 / weight 700`).
   3. **For each `SETTINGS` section**: a `Label` header (padding `18px 4px 8px`) with the section name, then a `Section` card.
   4. **Connected** group: `Label` **"Connected"** (padding `18px 4px 8px`), then a `Card radius=20` (padding `4px 16px`) listing `DEVICES`:
      - Each device row (gap 12, padding `11px 0`): a `30×30` radius-9 tile, background `d.on ? T.goodSoft : T.fieldFill`, `Ic laptop s=16` color `d.on ? T.good : T.text3`; name (`14px / 600 / T.ink`) + mono sub (`10.5px / T.text3`); if active, a `good` `Chip` **"Active"** (`fontSize 10`). `Rule` between devices.

### Notes
- All sections render in full, stacked. Only nav back has an action; info button and the rows are visual.

---

## iPad — `PadSettings`

Two-region layout: a fixed left sidebar (account + section nav + devices) and a scrolling detail column. `active` section index state (initial 0).

### Layout
1. **`PadStatusBar`** (pinned).
2. **Content** (absolute inset 0, `top 30`, row, gap 18, padding 24):
   - **Sidebar** (width 272, flex column, gap 14):
     - **Account card** (`Card radius=22`, padding 16):
       - Row (gap 12): `Avatar s=56`; name **"Adam Nolle"** (`16px / 720 / -0.3`), mono **"adam@nolle.studio"** (`10px / T.text3`), accent `Chip` **"PRO · ARCHIVAL"** (`fontSize 9, marginTop 5`).
       - `Rule` (`margin 14px 0`).
       - Section nav list (column gap 2): one button per `SETTINGS` section — row (gap 11, padding `9px 10px`, radius 11), background `T.fieldFillHi` when active else transparent; `Ic name={sec.icon} s=16` color `active ? T.accent : T.text2`; name (`13.5px`, weight active 650 else 500, color active `T.ink` else `T.text2`); right mono count = `sec.rows.length` (`10.5px / T.text3`). Tap → `setActive(i)`.
       - Then 3 static link rows **"Account"**, **"Plan & billing"**, **"About"** (`13.5px / 500 / T.text2`) each with `Ic chev s=13 c=T.text4` (no action).
     - **Connected card** (`Card radius=20`, padding 16): `Label` (color `T.good`) **"Connected"**; list of `DEVICES` (gap 12): `28×28` radius-8 tile (`d.on ? T.goodSoft : T.fieldFill`, `Ic laptop s=14` color `d.on ? T.good : T.text3`), name (`12.5px / 600`) + mono sub (`10px / T.text3`), and an `8×8` `T.good` dot if active.
   - **Main detail** (scroll, flex 1):
     - `Label` (color `T.accentText`) **"3DSeen · {active section name}"**.
     - Big title = active section name at `38px / weight 730 / letterSpacing -1.4 / lineHeight 1.02 / marginTop 6`.
     - Subtitle **"Settings that apply to every new scan unless overridden in the briefing."** (`13.5px / T.text2 / marginTop 8`).
     - The active section as a `Section` card (marginTop 18).
     - **"Glance" grid** (`1fr 1fr`, gap 14, marginTop 18): every *other* section (all except the active one) rendered as a small `Label` header + `Section` card.

### Device differences vs iPhone
- Master/detail: section nav lives in the sidebar; detail shows the selected section large plus a 2-up glance grid of the remaining sections.
- Adds email + "PRO · ARCHIVAL" and per-section row counts.

---

## Mac — `MacSettings` (preferences window)

Native-prefs layout: left sidebar 248 + right detail with its own toolbar and search. `active` index state (initial 0).

### Sidebar (width 248)
- Background `T.card2`, `borderRight 0.5px T.line`, padding **`52px 14px 18px`** (top 52 clears the traffic-light row; this sidebar runs full height with NO separate title bar above it).
- **Account header** (row gap 11, padding `4px 8px 14px`): `Avatar s=44`; name **"Adam Nolle"** (`14.5px / 700 / -0.3`) + mono **"PRO · ARCHIVAL"** (`9.5px / T.text3`).
- **Section nav** (column gap 2): one button per section — row (gap 11, padding `8px 10px`, radius 9), background **`T.accent`** when active else transparent (note: full accent fill, unlike iPad's `fieldFillHi`); `Ic name={sec.icon} s=16` color `active ? T.onAccent : T.text2`; name (`13.5px`, weight active 600 else 500, color active `T.onAccent` else `T.ink`). Tap → `setActive(i)`.
- `Rule` (`margin 8px 8px`).
- 4 static rows **"Account"**, **"Plan & billing"**, **"Devices"**, **"About"** (`13.5px / 500 / T.text2`, no chevron, no action).
- Spacer, then **Connected** `Card inset radius=14` (padding 13): `Label` (color `T.good`) **"Connected"**; each device row (gap 9): `8×8` dot (`d.on ? T.good : T.text4`), name (`12.5px / 600 / T.ink`), and a right mono token = `d.s.split(' · ')[1]` (the second half of the sub, e.g. **"M4 Max"** / **"M2"**) at `9.5px / T.text3`.

### Detail pane (flex 1, column)
1. **Toolbar** (height 52, `borderBottom 0.5px T.line`, background `T.card2`, padding `0 22px`, row gap 12):
   - Back chip-button (height 30, radius 8, `T.fieldFill`, `Ic back s=15 c=T.text2`, **"Library"**) → `go('library')`.
   - Active section name (`15px / 700 / -0.3 / T.ink`).
   - Spacer.
   - A search field mock: `height 32`, padding `0 12px`, radius 9, `T.fieldFill`, width 220, `inset 0 0 0 0.5px T.line`; `Ic search s=15 c=T.text3` + placeholder **"Search settings"** (`13px / T.text3`).
2. **Scroll content** (padding 28), centered column `maxWidth 720`:
   - `Label` (color `T.accentText`) **"3DSeen Studio · Preferences"**.
   - Title = active section name (`30px / weight 730 / letterSpacing -1 / marginTop 6`).
   - Subtitle **"Defaults applied to every new scan and handoff. Override per-project in the capture briefing."** (`14px / T.text2 / lineHeight 1.45 / marginTop 8`).
   - Active `Section` card (marginTop 20).
   - **Only when `active === 0`** (Capture defaults): an extra block (marginTop 22) — `Label` **"Also in capture defaults"** then a `Section` for `SETTINGS[1]` (Compute & handoff).

### Device differences
- Mac sidebar uses **solid accent** for the selected section (iPad uses a subtle `fieldFillHi`; iPhone has no nav). Sidebar starts at top with a 52px inset (no separate title bar over it) while the detail pane has its own 52px toolbar with back + search.
- Connected list collapses to dot + name + chip-id (just the chip name like "M4 Max").
- Extra "Also in capture defaults" cross-section block appears only on the first section.

---

## Implementation notes for SwiftUI
- **`SettingRow` ownership of toggle state**: each row holds its *own* `useState(!!row.toggle)` — there is no central store and `onToggle` is never wired. Replicate with per-row `@State`; the screen is a static design mock. The "Smart offload" row has both `v` and `toggle:true` → render the **toggle** (presence of `toggle` wins).
- **Section is the reusable atom** across all three variants — a `Card radius=20, padding 4px 16px` with `Rule`-separated rows. Build once.
- **Mac selected-section styling is solid accent** (`background T.accent`, text/icon `T.onAccent`) — visually distinct from iPad's `T.fieldFillHi` highlight. Don't unify them.
- **Sidebar top insets**: Mac sidebar uses `52px` top padding to clear traffic lights and runs full-height; the detail toolbar is a separate 52px bar. iPad content starts at `top 30` under `PadStatusBar`.
- **Dynamic title binding**: iPad/Mac headers interpolate `SETTINGS[active].sec` in the eyebrow label, the big title, and (Mac) the toolbar title — all from one source.
- **iPad glance grid** = `SETTINGS.filter((_, i) => i !== active)` in a 2-col grid; Mac instead shows a single fixed extra section (SETTINGS[1]) only on the first tab.
- **Connected device chip-id parsing** on Mac: `d.s.split(' · ')[1]` → show only the SoC ("M4 Max"/"M2"). Keep the full sub on iPhone/iPad.
- Avatar gradient endpoint `#1B3A8C` is a literal (a deep blue) paired with `T.accent`.
