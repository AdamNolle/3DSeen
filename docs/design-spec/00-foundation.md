# 3DSeen Studio — Foundation Spec (design system)

Canonical reference for tokens, components, render helpers, icons, data, and flows.
Source of truth: `docs/design-ref/ds.jsx`, `render.jsx`, `frames.jsx`, `icons.jsx`, `data.jsx`.
Aesthetic: precise-instrument, bright/legible, **one cobalt accent**, refined Liquid Glass, warm-paper light + true-dark. No neon, no glow.

The live theme is a token bag `T`; `setTheme('dark'|'light')` swaps it. In Swift this maps to the `St` theme (see `Sources/Shared/DesignSystem/Theme.swift`) resolved from color scheme.

---

## 1. Color tokens (exact)

| token | LIGHT | DARK |
|---|---|---|
| canvas | `#E9E7E1` | `#0C0C0E` |
| bg | `#F6F5F2` | `#161619` |
| bgInset | `#EDEBE5` | `#101013` |
| card | `#FFFFFF` | `#1F1F25` |
| card2 | `#FBFAF8` | `#1A1A1F` |
| ink | `#1B1B1D` | `#F3F2F5` |
| text2 | `rgba(27,27,29,0.60)` | `rgba(243,242,245,0.62)` |
| text3 | `rgba(27,27,29,0.40)` | `rgba(243,242,245,0.40)` |
| text4 | `rgba(27,27,29,0.26)` | `rgba(243,242,245,0.24)` |
| onAccent | `#FFFFFF` | `#0A1124` |
| line | `rgba(20,20,24,0.08)` | `rgba(255,255,255,0.08)` |
| lineStrong | `rgba(20,20,24,0.14)` | `rgba(255,255,255,0.15)` |
| fieldFill | `rgba(20,20,24,0.045)` | `rgba(255,255,255,0.06)` |
| fieldFillHi | `rgba(20,20,24,0.075)` | `rgba(255,255,255,0.10)` |
| accent | `#2D68F0` | `#5E9BFF` |
| accentText | `#1F58DC` | `#84B2FF` |
| accentSoft | `rgba(45,104,240,0.10)` | `rgba(94,155,255,0.16)` |
| accentLine | `rgba(45,104,240,0.30)` | `rgba(94,155,255,0.34)` |
| good | `#1E8E5A` | `#34C77B` |
| goodSoft | `rgba(30,142,90,0.12)` | `rgba(52,199,123,0.16)` |
| warn | `#B6791D` | `#E0A53F` |
| warnSoft | `rgba(182,121,29,0.14)` | `rgba(224,165,63,0.16)` |
| bad | `#C53B30` | `#FF6B5E` |
| badSoft | `rgba(197,59,48,0.12)` | `rgba(255,107,94,0.16)` |
| glassFill | `rgba(255,255,255,0.72)` | `rgba(34,34,40,0.66)` |
| glassBorder | `rgba(20,20,24,0.07)` | `rgba(255,255,255,0.10)` |
| glassShine | `rgba(255,255,255,0.9)` | `rgba(255,255,255,0.14)` |
| primaryFill | `#1B1B1D` | `#F3F2F5` |
| primaryText | `#FFFFFF` | `#16161A` |
| stageRim | `rgba(255,255,255,0.6)` | `rgba(255,255,255,0.10)` |
| grid | `rgba(20,20,24,0.07)` | `rgba(255,255,255,0.07)` |
| axis | `rgba(20,20,24,0.16)` | `rgba(255,255,255,0.18)` |

**Shadows (CSS box-shadow → SwiftUI layered shadows):**
- `glassShadow` light: `0 1px 2px rgba(20,20,30,.06), 0 12px 32px rgba(20,20,30,.10)`; dark: `0 1px 2px rgba(0,0,0,.4), 0 16px 40px rgba(0,0,0,.5)`
- `cardShadow` light: `0 1px 2px rgba(20,20,30,.04), 0 10px 30px rgba(20,20,30,.06)`; dark: `0 1px 2px rgba(0,0,0,.3), 0 12px 34px rgba(0,0,0,.42)`
- `cardShadowLg` light: `0 2px 6px rgba(20,20,30,.05), 0 24px 60px rgba(20,20,30,.10)`; dark: `0 2px 8px rgba(0,0,0,.4), 0 28px 70px rgba(0,0,0,.55)`
- `primaryShadow` light: `0 1px 2px rgba(0,0,0,.18), 0 6px 16px rgba(0,0,0,.16)`; dark: `0 1px 2px rgba(0,0,0,.4), 0 8px 20px rgba(0,0,0,.4)`

**Stage gradient (3D backdrop):** light `radial-gradient(125% 110% at 50% 8%, #FCFCFB 0%, #EFEEE9 52%, #E2E0DA 100%)`; dark `radial-gradient(125% 110% at 50% 6%, #2A2A31 0%, #17171B 55%, #101013 100%)`.

**STONE** (warm-stone material for rendered 3D objects, theme-independent): hi `#ECE4D6`, mid `#BFA98C`, lo `#6B5C49`, deep `#372E24`.

---

## 2. Typography
- `sf` = `"SF Pro Display","SF Pro Text",-apple-system,system-ui` → iOS/macOS **system font**. Large titles use Display weights; body uses Text.
- `mono` = `"SF Mono",ui-monospace,Menlo` → `.system(.body, design: .monospaced)`. Used for: `Label` overlines, `Stat` keys, numeric readouts, badges. Numbers use **tabular figures** (`.monospacedDigit()` / `font-variant-numeric: tabular-nums`, the `.st-num` class).
- Common weights seen: 600 (semibold), 650/680/700/720 (heavy display), letter-spacing negative on titles (−0.3 to −0.6), positive on overlines (+1 to +1.4).

---

## 3. Components (exact specs)

- **Glass** (Liquid Glass floating panel) — `radius=18` default. Recipe: translucent fill (`glassFill`), `backdrop blur(24px) saturate(200%) brightness(1.02 light / 1.05 dark)`, `0.5px` border (`glassBorder`), `glassShadow`. Shine overlay: specular top rim `inset 0 0.9px 0 glassShine` + faint inner light + soft bottom inner shade `inset 0 -10px 22px rgba(18,18,28,.05)` + top sheen `linear-gradient(177deg, rgba(255,255,255,.38) 0%, transparent 26%)`. **`tone='dark'`** variant (glass over camera feed): fill `rgba(26,24,21,.52)`, border `rgba(255,255,255,.18)`, rim `rgba(255,255,255,.55)`, sheen `rgba(255,255,255,.12)`. SwiftUI: `.ultraThinMaterial`/`.regularMaterial` + overlays, or custom blur.
- **Card** — `radius=20`. bg `card` (or `bgInset` if `inset`). `0.5px` `line` border. shadow `cardShadow` (or `cardShadowLg` if `elevated`, none if `inset`).
- **Button** — radius `999`, weight 600, ls −0.2, gap 8, centered. Heights: lg `52`, md `44`, sm `36`. Font: lg `16`, md `15`, sm `13.5`. Padding sm `0 14`, else `0 20`. Kinds: `primary` (primaryFill / primaryText / primaryShadow), `accent` (accent / onAccent / soft accent shadow), `secondary` (fieldFill / ink / inset 0.5px line), `ghost` (transparent / text2), `glass` (glassFill / ink / blur20 / inset border + glassShadow). `full` → width 100%.
- **Label** (overline) — mono, `10.5px`, weight 600, ls `1.4`, uppercase, color `text3`.
- **Stat** — key: mono `9.5px` w600 ls1 caps text3; value: tabular, sizes xl `40` / lg `28` / md `22` / sm `17`, weight 680, ls −0.6, lineHeight 1.04; unit: `0.46×` value size, w600 text3. `align` left/right.
- **Segmented** — pill container padding 3, radius 999, bg `fieldFill`, `inset 0.5px line`, gap 2. Items height md `36` / sm `30`, padding `0 14`, radius 999. Selected: bg `card` + small shadow + color `ink`; unselected color `text2`, font 13.5(md)/12.5(sm) w600.
- **Toggle** — `50×30`, padding 2, knob `26×26` white (shadow). On → bg `good`, knob right. Off → bg `fieldFillHi`, inset 0.5px line, knob left. transition .2s.
- **Chip** — padding `4×10`, radius 999, font 12 w600 ls −0.1, gap 5. Tones: neutral (fieldFill/text2/line), accent (accentSoft/accentText/accentLine), good (goodSoft/good), warn (warnSoft/warn), bad (badSoft/bad).
- **Meter** — height `6` default, radius `99`, track `fieldFillHi`, fill `accent` (overridable), width `value×100%`, animated width .5s.
- **Ring** — size `72`, stroke `7`. Track circle (color `line`) + value arc (color `accent`, `strokeDasharray` = circumference, rotate −90°, round cap). Center: `label` (font `size×0.3` w700 ink) + `sub` (mono 8.5 w600 text3).
- **Rule** — `0.5px` `line` divider; `vertical` → width .5 stretch.

---

## 4. Animations / motion
Keyframes: `st-fade` (opacity), `st-rise` (translateY 10→0 + fade), `st-pop` (scale .96→1 + fade), `st-sheen` (translateX −120%→260%, button shimmer), `st-spin` / `st-orbit` (rotate 360, loaders/orbit), `st-pulse` (opacity .5↔1, REC dot / live coverage). Tap feedback `.st-tap:active { transform: scale(.97) }` → SwiftUI `.scaleEffect` on press. **Entrance classes resolve to a fully-visible resting state** (no dependency on animation clock) — first paint always visible; micro-motion is additive.

---

## 5. Render helpers (`render.jsx`) — illustration vs real-3D mapping
- **HeroModel** — classical bust + plinth, warm STONE material, soft accent rim. `material`: `pbr` (default, gradient body), `wire` (cobalt wireframe), `metal` (cool greys), `matte` (flattened). **Decorative SVG → in the app should be a real interactive 3D model** (SceneKit/RealityKit/MetalSplatter), with material toggles mirroring pbr/wire/metal/matte.
- **CoverageDome** — 3 concentric shell rings of 30 wedges, status-colored (good/warn/bad), drop markers numbered 1..n. Used in briefing/review coverage. **Map to real coverage viz or faithful 2D.**
- **CoverageSphere** — wedge sphere (22 wedges), `covered`/`partial`/`bad` index sets, latitude lines, `pct` readout. Used in viewfinder/compact tiles. **Live capture coverage HUD.**
- **ScanThumb** — studio render of a scan keyed by `scan.tone` via `SCAN_TONES`: bone `#EFE7D7/#9B8769`, rust `#D8AE7E/#7A4F2E`, walnut `#C0A079/#5E4129`, graphite `#D2D4D8/#5A5E66`, slate `#AEB9BD/#4C5A60`, ice `#CFE0E2/#566C70`. Aspect `1/1.16`, radius 14, mode badge top-left (glass), name + `mode · tier · mb MB` label bottom. **Library cards** — can be Canvas/gradient render or real thumbnail.
- **Spark** — sparkline (w110 h30), fill 10% + 1.6px stroke + end dot. **Swift Charts / Canvas.**
- **Histogram** — RGB luma 3-channel (red/green/blue curves). **Canvas.**
- **FrameStrip** — row of captured-frame thumbnails, some marked rejected (×). **Review screen.**

---

## 6. Icons (`icons.jsx`) — names available (choose SF Symbol equivalents)
`back, chev, chevDown, close, plus, check, search, more, grid, list, settings, cube, room, landscape, sparkle, camera, scan, bolt, chip, laptop, phone, tablet, thermal, ruler, layers, share, export, download, airdrop, pin, light, focus, refresh, speed, hand, warning, info, clock, folder, cloud, lock, user, globe, wifi, battery, play, trash, copy`
Stroke set, `strokeWidth 1.7`, round caps, `viewBox 0 0 24 24`, defaults to currentColor.

---

## 7. Data (`data.jsx`) — verbatim
**SCANS** (8): `Celestial Bust` Object/Today/184MB/Full/bone/4.2M · `Amaranth Vase` Object/5d/92/Medium/rust/1.2M · `Studio Floor 02` Space/1w/412/Full/graphite/5.1M · `Walnut Desk` Object/1w/76/Reduced/walnut/480k · `Granite Falls` Landscape/2w/1140/Raw/slate/16M · `Archive Shelf` Space/3w/264/Full/ice/3.4M · `Ceramic Pour` Object/3w/58/Preview/bone/120k · `Cassette Maxell` Object/Aug 04/124/Full/graphite/4.0M.

**EXPORT_FORMATS** (6): USDZ `.usdz` 184 MB "AR Quick Look · Apple-native" **(best)** · USD `.usdc` 212 MB "Pixar OpenUSD · pipelines" · glTF `.glb` 156 MB "Universal · web · Blender" · OBJ `.obj + mtl` 298 MB "Legacy DCC interchange" · FBX `.fbx` 188 MB "Unreal · Unity · Maya" · PLY `.ply` 440 MB "Point cloud · raw archive".

**MEASUREMENTS** (3): M01 "Height · chin to crown" 14.20 cm · M02 "Shoulder width" 11.84 cm · M03 "Nose to ear" 3.10 cm.

**DROPS** (3, coverage gaps): crown "Crown of head" high (50,22) "Lift camera 25° higher" · earl "Back-left ear" med (24,42) "Walk 15° clockwise" · under "Underside" med (50,84) "Tilt down 25°".

---

## 8. Flows & device registry
- **FLOWS** — phone & pad: `library → mode → briefing → viewfinder → quality → review → compute → viewer → export → settings`. mac: `library → viewer → compute → export → settings` (no wizard capture flow on Mac).
- **SCREEN_TITLES**: library "Library", mode "New Scan", briefing "Briefing", viewfinder "Capture", quality "Detail", review "Review", compute "Compute", viewer "Model", export "Export", settings "Settings".
- **DEVICE_DIMS** (prototype): phone 402×874, pad 1194×834 (landscape), mac 1440×900.
- **Device mapping to the real apps:** iPhone variants → iOS compact; iPad variants → iOS regular (bespoke split/sidebar, NOT mere width reflow); Mac variants → the macOS target (window + sidebar + detail + inspector).

---

## 9. Implementation notes (SwiftUI)
- Tokens already exist as the `St` theme (`Theme.swift`). **Audit every hex against §1** — exactness matters (warm paper, true dark).
- Liquid Glass: prefer `.regularMaterial`/`.ultraThinMaterial` with a token-tinted overlay + the specular rim/inner-shade overlays for fidelity; the dark `tone` variant is essential over the camera feed.
- The bust/coverage SVGs are **decorative stand-ins** — in the shipping app the Viewer's model area is a real 3D scene (MetalSplatter / SceneKit). Thumbnails/charts may stay rendered.
- iPad and Mac are **first-class bespoke layouts**, not reflowed phone screens — see each screen spec's "Device differences".
