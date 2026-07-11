# Finished 3D Model Viewer — SwiftUI implementation spec

Source: `studio/screens/viewer.jsx`. Exports `PhoneViewer`, `PadViewer`, `MacViewer`, `MATERIALS`. Purpose: inspect a finished reconstruction — orbit the model, switch material, take measurements, jump to AR / Export.

> **FIDELITY CAVEAT.** This is the one file the DesignSync proxy returned only lossily ("1077 items compressed to 51"). Everything in this spec that describes a **container, a literal copy string, a numeric metric, the `MATERIALS`/`MEASUREMENTS` wiring, the Mac tool-rail array, or the `<Segmented>` options is VERBATIM** (the template survived intact). Items tagged **[RECOVERED]** were pulled from the surviving 51-fragment sample (high confidence). Items tagged **[PATTERN]** are reconstructed from the identical idioms in the verbatim `compute.jsx`/`export.jsx` (structure certain, a prop may differ). Items tagged **[INFERRED]** had no surviving fragment — their position is verbatim but the inner content is a best guess. The `docs/design-ref/screens/viewer.jsx` file mirrors these tags inline.

Tokens: accent `#2D68F0`/`#5E9BFF`; `T.mono` for all `st-num` text. Glass buttons use `T.glassFill` + `backdropFilter blur(18px)` + `T.glassShadow`.

---

## Shared data & sub-components

### `MATERIALS` (VERBATIM) — 4 swatches, each `{ id, l, g:[from,to] }` (radial gradient stops)
1. `pbr` — **"PBR"** — gradient `#BFA98C → #6B5C49` (warm bronze).
2. `matte` — **"Matte"** — `#E2D8C6 → #8B7B62` (sand).
3. `metal` — **"Metal"** — `#E8E6E2 → #5A5E63` (steel).
4. `wire` — **"Wire"** — `#9BC0FF → #2D68F0` (cobalt).

### `MEASUREMENTS` (from data.jsx) — rendered list, fields `id`, `l` (label), `v` (value), `u` (unit)
- The Pad/Mac measurement lists iterate `MEASUREMENTS`. The first row's `id` is **`M01`** (used to suppress the top border on the first row: `borderTop` applied only when `m.id !== 'M01'`). There are **3 pins** (the section header literally says "3 pins"). One recovered value is **"14.20 cm"**. Pull exact rows from `data.jsx`.

### `ToolRail({ items, active, onPick, vertical=true, labels=false })` — [INFERRED body]
- Props are VERBATIM (signature survived). The body is reconstructed as a glass pill of icon buttons; vertical on Phone/Pad. Suggested: `Glass` container, each item a `~44×44` button, background `T.accent` when `it.id === active` else transparent, `Ic name={it.i}` colored `T.onAccent`/`T.text2`, optional label when `labels`. Tap → `onPick(it.id)`. (The Mac variant does NOT use this component — it inlines its own rail, see below, which gives the canonical button styling: `42×42`, radius 11, `background on ? T.accent : transparent`.)

### `MaterialPicker({ value, onChange, compact=false })` (VERBATIM)
- Row of 4 equal buttons (gap 6). Each: padding `compact ? '7px 4px' : '9px 6px'`, radius 14; background `T.fieldFillHi` + `inset 0 0 0 1px T.accentLine` when selected, else transparent. A `30×30` round swatch with `radial-gradient(circle at 32% 28%, g[0], g[1])` + `inset 0 1px 1px rgba(255,255,255,0.5)`. Label `m.l` (`10.5px`, weight selected 700 else 500, color selected `T.ink` else `T.text3`). Tap → `onChange(m.id)`.

### `MeasureOverlay({ vb, lines })` — [INFERRED line element]
- An absolutely-positioned full-size `<svg>` with `viewBox={vb}`, `pointerEvents none`. Maps `lines` to leader-line elements (reconstructed as dashed accent lines with endpoint dots). The wrapper/props are VERBATIM; the per-line markup is a guess.

---

## iPhone — `PhoneViewer`

Full-bleed immersive viewer with floating glass chrome. State: `mat` (initial `'pbr'`), `tool` (initial `'orbit'`).

### Layout (back → front)
1. **Stage** [PATTERN]: full-bleed `Stage` + `HeroModel` driven by `mat` (the orbiting hero render).
2. **Legibility scrim** [INFERRED]: a subtle top/bottom dark gradient over the stage.
3. **`StatusBar`** [PATTERN]: light tone over the dark stage.
4. **Top bar** (VERBATIM container): absolute `top 56, left/right 14`, row gap 8.
   - Left: glass round button `38×38` radius 999 (`T.glassFill` + blur 18 + `T.glassShadow`) → `go('library')`; icon **[RECOVERED] `Ic back s=18 c=T.ink`**.
   - Center [INFERRED]: a glass title pill (model name "Celestial Bust").
   - Right: glass round button `38×38` → `go('export')`; icon [INFERRED] `Ic export …`.
5. **Tool rail** (VERBATIM container): absolute `top 110, right 14` → `ToolRail` [INFERRED items] bound to `tool`/`setTool` (vertical, right-edge).
6. **Measure callout** — only when `tool === 'measure'` (VERBATIM container at absolute `left 52, top 326`): **[RECOVERED]** a `Glass radius=10` (padding `5px 10px`) with mono **"14.20 cm"** (`12px / 700 / T.accentText`).
7. **Bottom inspector** (VERBATIM container): absolute `bottom 26, left/right 14`, column gap 8.
   - **[RECOVERED] Stats/material card** — `Glass radius=22` padding 14:
     - Header (baseline space-between): `Label` (color `T.good`) **"Captured today · Object · Full"** + mono **"v2"** (`11px / T.text3`).
     - Stats grid `repeat(4,1fr)` gap 8 marginTop 12: `Stat Tris 4.2M`, `Stat Tex 4K`, `Stat PSNR 38.7`, `Stat Scale 14cm` (all `size=sm`).
     - `MaterialPicker value={mat} onChange={setMat} compact` (marginTop 12).
   - **Action row** (gap 8): `Button kind="glass" flex:1` with **[RECOVERED] `Ic scan s=16 c=T.ink`** + **"AR"**; `Button kind="accent" flex:1.5` with **[RECOVERED] `Ic export s=16 c=T.onAccent`** + **"Export"** → `go('export')`.

### Interactions
- Library back → `library`; top-right + Export button → `export`; tool rail sets `tool` (selecting `measure` reveals the callout); material picker sets `mat`.

---

## iPad — `PadViewer`

Same immersive stage with a left tool rail, a right inspector column, and a bottom environment bar. State: `mat`, `tool`, plus `env` (initial **`'Studio'`**).

### Layout (VERBATIM containers; inner content as tagged)
1. **Stage** [PATTERN] + **scrim** [INFERRED] + **`PadStatusBar`** [PATTERN, light].
2. **Top bar**: absolute `top 36, left/right 18`, row gap 10.
   - Glass round `40×40` → `go('library')`, icon **[RECOVERED] `Ic back s=18 c=T.ink`**.
   - [INFERRED] glass title pill + meta chip (model name + "FULL · 4.2M · 184 MB").
   - Spacer (`flex 1`).
   - `Button kind="glass" size="sm"` [INFERRED icon] + **"AirDrop"**; `Button kind="accent" size="sm"` [INFERRED icon] + **"Export"** → `go('export')`.
3. **Left tool rail**: absolute `top 96, left 18` → `ToolRail` [INFERRED items] bound to `tool` (vertical, likely with labels).
4. **Measure callouts** — only when `tool === 'measure'` (VERBATIM positions): two absolutely-placed callouts at `left 358, top 350` and `left 700, top 305` (each a Glass measurement pill like the iPhone "14.20 cm" one) [PATTERN/INFERRED values].
5. **Right inspector**: absolute `top 96, right 18, bottom 18`, **width 326**, column gap 12. Three stacked cards [INFERRED contents, positions VERBATIM] — geometry stats, material override (`MaterialPicker`), and a measurements list iterating `MEASUREMENTS`.
6. **Bottom env bar**: absolute `bottom 18, left 110, right 360`, centered → [INFERRED] an environment/lighting selector bound to `env`/`setEnv` (e.g. Studio / Sunset / …).

### Device differences vs iPhone
- Tool rail moves to the **left**; a persistent **right inspector column** (width 326) replaces the iPhone bottom card; adds a **bottom environment bar** and an `env` state. Chrome buttons live in a top bar with title + meta + AirDrop/Export.

---

## Mac — `MacViewer`  (this variant is VERBATIM except the noted slots)

Classic 3-pane desktop: 52px toolbar; left tool rail (64); center stage (flex); right inspector (320).

### Toolbar (height 52, VERBATIM)
- `borderBottom 0.5px T.line`, background `T.card2`, padding `0 18px 0 84px` (traffic-light inset).
- Left→right: back chip-button (height 30, radius 8, `T.fieldFill`, **[RECOVERED] `Ic back s=15 c=T.text2`**, **"Library"**) → `go('library')`; **[PATTERN] vertical `Rule` height 22**; a green status dot `8×8` (`T.good`); title **"Celestial Bust"** (`15px / 700 / -0.3`); mono meta **"FULL · 4.2M · 184 MB"** (`12px / T.text3`); spacer; `Segmented size="sm" options={['Inspect','AR','Compare','Slice']} value="Inspect"` (VERBATIM, static `onChange`); `Button kind="ghost" size="sm"` **[RECOVERED] `Ic airdrop s=15 c=T.text2`** + **"AirDrop"**; `Button kind="accent" size="sm"` **[RECOVERED] `Ic export s=15 c=T.onAccent`** + **"Export…"** → `go('export')`.

### Body (flex row)
1. **Tool rail** (width 64, VERBATIM): `borderRight 0.5px T.line`, background `T.card2`, centered column, padding `14px 0`, gap 4. Iterates a VERBATIM inline array:
   - `orbit`→icon `cube`, `measure`→`ruler`, `pin`→`pin`, `layers`→`layers`, `light`→`light`, `ar`→`scan`, `slice`→`focus`.
   - Each is a `42×42` button, radius 11, background **`T.accent` when `it.id === tool`** else transparent; **[RECOVERED] `Ic name={it.i} s=20 c={on ? T.onAccent : T.text2}`**. Tap → `setTool(it.id)`.
2. **Stage** (flex 1, relative, VERBATIM container):
   - **[PATTERN]** full-bleed `Stage` + `HeroModel w=620 h=620` (driven by `mat`).
   - **[INFERRED]** top-left status chip (absolute `top 18, left 18`).
   - **Floating env bar** (VERBATIM position: absolute `bottom 20`, horizontally centered) → **[INFERRED]** environment selector (Glass + Segmented).
3. **Inspector** (width 320, scroll, VERBATIM): `borderLeft 0.5px T.line`, background `T.card2`, padding 18, column gap 16.
   - **Geometry** block: `Label` (color `T.accentText`) **"Geometry"**; a `1fr 1fr` grid (gap 14, marginTop 12) of **[INFERRED] 4 `Stat`s** (triangles / vertices / textures / size — exact labels not recovered).
   - **[PATTERN] `Rule`**.
   - **Material override** block: `Label` **"Material override"**; **[PATTERN] `MaterialPicker value={mat} onChange={setMat}`** (marginTop 12).
   - **[PATTERN] `Rule`**.
   - **Measurements** block: `Label` (color `T.good`) **"Measurements · 3 pins"** (VERBATIM). List iterates `MEASUREMENTS` (VERBATIM): each row (gap 10, padding `8px 0`, `borderTop 0.5px T.line` except first where `m.id === 'M01'`) — **[INFERRED] leading pin-index dot** + `m.l` (`13px / T.text2`, flex 1) + `m.v m.u` (`14px / 700 / T.ink`, mono). Then a 2-button row (gap 8, marginTop 12): `Button secondary size=sm flex:1` **[RECOVERED] `Ic plus s=15 c=T.ink`** + **"Add pin"**; `Button secondary size=sm flex:1` **[RECOVERED] `Ic download s=15 c=T.ink`** + **"CSV"**.

### Device differences
- Mac adds the top `Segmented` mode switch (Inspect / AR / Compare / Slice) and a full 7-tool left rail (orbit, measure, pin, layers, light, ar, slice) vs the smaller floating rails on Phone/Pad. The inspector is a fixed 320 right column with Geometry / Material / Measurements blocks and Add-pin / CSV actions. The 84px toolbar inset and `T.card2` panels match the other Mac screens.

### Dynamic / animated
- Constant: the hero `HeroModel` orbit/sheen (material-dependent). Measurement overlay/callouts appear conditionally on `tool === 'measure'`. Material switching re-skins the model live.

---

## Implementation notes for SwiftUI
- **Trust the VERBATIM skeleton, treat tagged slots as guidance.** Containers, copy ("Celestial Bust", "FULL · 4.2M · 184 MB", "Captured today · Object · Full", "Measurements · 3 pins", "Add pin", "CSV", the `Segmented` options), absolute positions, widths (Pad inspector 326, Mac rail 64 / inspector 320), and the tool-rail icon set are all real and pixel-trustworthy. The icon `name`/`size`/`color` on RECOVERED buttons are real. INFERRED inner content (title pills, geometry stat labels, env options, scrim gradients, pin dot) should be confirmed against the live design before final polish.
- **Glass chrome over an immersive stage** is the defining look on Phone/Pad: round `38–40px` buttons using `T.glassFill` + a real backdrop blur (`.background(.ultraThinMaterial)` analog) + `T.glassShadow`. The model fills the whole screen; chrome floats.
- **Mac inline tool rail is the canonical rail styling** (use it to finalize the inferred `ToolRail` body): `42×42`, radius 11, `background on ? T.accent : transparent`, `Ic s=20 c={on ? T.onAccent : T.text2}`. The 7 tools and their icons are verbatim.
- **`MEASUREMENTS` first-row border trick**: suppress the top divider when `m.id === 'M01'`; all later rows get a `0.5px T.line` top border. Confirm the full row set + the leading pin marker from `data.jsx`.
- **Material binding** (`mat`) should re-render the hero in all three variants; `MATERIALS` gradients are for the picker swatches, not the 3D material itself (the 3D `HeroModel material=` takes `pbr|wire|metal|matte` — same ids).
- **Three rail placements**: Phone right-floating, Pad left-floating (likely labeled), Mac fixed 64px left column. Don't assume one component covers all three pixel-perfectly — the Mac one is inlined separately in the source.
- **Reuse the shared Mac toolbar** (52 / `0 18px 0 84px` / `T.card2` / `0.5px T.line`) exactly as in compute/export/settings; here it additionally hosts the `Segmented` mode switch.
- If exact fidelity on the INFERRED regions matters, re-fetch `studio/screens/viewer.jsx` through a path that bypasses the summarizing proxy — the underlying design file is intact; only this transport compressed it.
