# Spec — Scene Briefing & Guidance (`briefing.jsx`)

Source: `studio/screens/briefing.jsx` (verbatim). Screen key `'briefing'`. Step 2 of 4. Variants present: **Phone** (`PhoneBriefing`), **Pad** (`PadBriefing`). **No Mac variant.**
Exports: `PhoneBriefing`, `PadBriefing`, `CHECKLIST`, `GUIDES`.
Flow: back → `go('mode')`; close → `go('library')`; continue → `go('quality')` (the "Detail" step).

---

## Data

### `CHECKLIST` (6 items)
| id | label | status | detail | icon (`i`) |
|---|---|---|---|---|
| light | `Even, diffuse lighting` | pass | `1842 lux measured` | `light` |
| reflect | `Reflective surfaces detected` | **warn** | `2 glossy regions — consider polarizer` | `warning` |
| distance | `Distance to subject` | pass | `42 cm · in range` | `ruler` |
| support | `Stable surface` | pass | `Turntable detected` | `cube` |
| thermal | `Device thermal` | pass | `Nominal · 31 °C` | `thermal` |
| storage | `Storage available` | pass | `244 GB free · ~3.4 GB needed` | `download` |

Phone shows `CHECKLIST.slice(0,4)` (first 4). Pad shows all 6. 5 pass / 1 warn → "5 of 6".

### `GUIDES` (4 items)
| t (title) | d (body) | icon (`i`) |
|---|---|---|
| `Move slowly` | `Keep angular velocity below 30 °/s. Walk a smooth orbit, not a stroll.` | `speed` |
| `Three passes` | `Eye-level, then high, then low — 360° each. Overlap by 60%.` | `refresh` |
| `Hands-free turntable` | `For objects under 30 cm, rotate the object — not the camera.` | `hand` |
| `Avoid shiny + clear` | `Glass, mirrors, water absorb poorly. Mark them or skip them.` | `warning` |

Phone shows `GUIDES.slice(0,2)`. Pad shows all 4.

---

## Sub-components

### `StatusDot({ status, s=28 })`
Circle `s×s`, `borderRadius:99; display:grid; placeItems:center; flexShrink:0`.
- color `c`: pass→`T.good`, warn→`T.warn`, else `T.bad`.
- bg: pass→`T.goodSoft`, warn→`T.warnSoft`, else `T.badSoft`.
- content: pass → `<Ic name="check" s={s*0.5} c={c} sw={2.6} />` ; otherwise a bold `!` glyph (color `c`, fontSize `s*0.5`, weight **800**, lineHeight 1).

### `CheckRow({ item })`
Row `flex; align center; gap:12; padding:'11px 0'`.
- `<StatusDot status={item.status} />` (default 28).
- Middle (`flex:1; minWidth:0`): label fontSize **14**, weight **600**, color `T.ink`, letterSpacing **-0.2**; detail (mono, `.st-num`) fontSize **11.5**, color `T.text3`, marginTop 2.
- Trailing: `<Ic name={item.i} s={16} c={T.text4} />`.

### `GuideCard({ guide })`
`<Card radius={16} style={{padding:14}}>`.
- Icon chip `32×32`, `borderRadius:10`, bg `T.accentSoft`, `display:grid; placeItems:center; marginBottom:10`; `<Ic name={guide.i} s={17} c={T.accent} />`.
- Title `{guide.t}`: fontSize **13.5**, weight **700**, letterSpacing **-0.2**, color `T.ink`.
- Body `{guide.d}`: fontSize **11.5**, color `T.text2`, lineHeight **1.4**, marginTop 4.

---

## PHONE — `PhoneBriefing`

Root `absolute; inset:0; background:T.bg`. `<StatusBar />` pinned.
Scroll body `.st-scroll`: `absolute; inset:0; top:54; overflow:auto; padding:'8px 20px 110px'`.

1. **Nav row** (`flex, space-between, center`): Back `36×36` circle bg `T.fieldFill` `<Ic name="back" s={17} c={T.text2}/>` → `go('mode')`; center `<Chip tone="neutral">Step 2 of 4</Chip>`; Close `36×36` circle `<Ic name="close" s={16} c={T.text2}/>` → `go('library')`.
2. **Title block** (`marginTop:18`): `<Label>Scene briefing</Label>` + H1 `You're ready in 5 of 6` (fontSize **28**, weight **720**, letterSpacing **-0.9**, lineHeight **1.05**, color `T.ink`, marginTop 6).
3. **Readiness card** `<Card radius={20}>` `padding:16; marginTop:14; flex; align center; gap:16`:
   - `<Ring value={0.83} size={74} color={T.good} label="83" />`
   - text: `Scan-readiness: Excellent` (fontSize **15**, weight **700**, letterSpacing **-0.3**); sub `Resolve the reflection warning to reach 100.` (fontSize **12.5**, color `T.text2`, marginTop 3, lineHeight 1.35).
4. **Checklist card** `<Card radius={20} style={{padding:'4px 16px', marginTop:12}}>`: first 4 `CHECKLIST` rows via `CheckRow`, with `<Rule />` between (not after last). Uses `React.Fragment` per row.
5. **Pro tips** heading (`marginTop:18; marginBottom:10`): `Pro tips for this scene` (fontSize **14**, weight **700**, letterSpacing **-0.2**, color `T.ink`).
6. **Guides grid** (`gridTemplateColumns:'1fr 1fr'; gap:10`): first 2 `GUIDES` as `GuideCard`.
7. **Pinned footer** `absolute; bottom:28; left:20; right:20`: `<Button kind="accent" full size="lg" onClick={() => go('quality')}>` leading `<Ic name="bolt" s={17} c={T.onAccent}/>` + `Continue to Detail`.

---

## PAD — `PadBriefing`

Root `absolute; inset:0; background:T.bg`. `<PadStatusBar />` pinned. Container `absolute; inset:0; top:30; display:flex; flexDirection:column; padding:24`. **Non-scrolling**, flex-fill.

1. **Header row** (`flex, space-between, center`):
   - Left (`flex; gap:12`): Back `38×38` circle `<Ic name="back" s={17} c={T.text2}/>` → `go('mode')`; title stack `<Label>New Scan · Step 2 of 4</Label>` + `Scene briefing & guidance` (fontSize **17**, weight **700**, letterSpacing **-0.3**, marginTop 2).
   - Center: `<StepTabs active={1} />` (from mode.jsx; "Briefing" active, "Mode" done).
   - Right: `<Button kind="ghost" size="sm" onClick={() => go('quality')}>Skip briefing</Button>`.
2. **Two-column body** (`flex:1; gridTemplateColumns:'1.05fr .95fr'; gap:16; minHeight:0; marginTop:18`):
   - **Left column — live preview** (`flex column; gap:14; minHeight:0`):
     - Preview frame (`flex:1; borderRadius:22; overflow:hidden; position:relative; minHeight:0; boxShadow:T.cardShadow`):
       - `<Stage radius={22}><HeroModel w={580} h={400} /></Stage>`.
       - Top-left overlay (`absolute; top:14; left:14; flex; gap:8`):
         - `<Chip tone="neutral" style={{background:T.glassFill, backdropFilter:'blur(14px)'}}>` `<Ic name="camera" s={13} c={T.text2}/> Live preview`.
         - `<Chip tone="accent">` with a `6×6` pulsing dot (`borderRadius:99; background:T.accent; animation:'st-pulse 1.4s infinite'`) + `AI watching`.
       - Bottom-left overlay (`absolute; bottom:14; left:14`): `<Glass radius={14} style={{padding:'10px 14px'}}>`:
         - `<Label color={T.good}>Auto-detected</Label>`
         - `Ceramic Vase · 14 cm` (fontSize **16**, weight **700**, letterSpacing **-0.3**, marginTop 4).
         - mono caption `conf 0.94 · 14.2 × 10.8 × 14.2 cm` (`fontFamily:T.mono`, fontSize **10.5**, color `T.text3`, marginTop 2).
     - Guides row (`gridTemplateColumns:'repeat(4,1fr)'; gap:10`): **all 4** `GUIDES`.
   - **Right column — readiness** (`flex column; gap:14; minHeight:0`):
     - Readiness card `<Card radius={22} style={{padding:20}}>` `flex; gap:18; align center`:
       - `<Ring value={0.83} size={104} stroke={8} color={T.good} label="83" sub="SCAN READY" />`.
       - text (`flex:1`): `<Label color={T.good}>Readiness · excellent</Label>`; `5 of 6 checks pass` (fontSize **22**, weight **720**, letterSpacing **-0.6**, marginTop 6); body (fontSize **13**, color `T.text2`, marginTop 6, lineHeight 1.4): `Resolve the reflection warning to push fidelity to ` + bold `4.2M tris` (color `T.ink`) + ` with confident PBR estimation.`
     - Checklist card `<Card radius={20} style={{padding:'4px 18px', flex:1, minHeight:0, overflow:'hidden'}}>`: **all 6** `CHECKLIST` rows, `<Rule />` between (not after last).
     - Action row (`flex; gap:10`):
       - `<Button kind="secondary" style={{flex:1}}>` `<Ic name="refresh" s={15} c={T.ink}/> Re-run analysis` (no onClick).
       - `<Button kind="accent" style={{flex:2}} onClick={() => go('quality')}>` `<Ic name="bolt" s={17} c={T.onAccent}/> Continue to Detail`.

---

## Device differences (Pad vs Phone)
- Phone: scrolls; 4-of-6 checklist; 2-of-4 guides; horizontal Ring(74) readiness card; single bottom CTA. Close button present.
- Pad: fixed two-column; left = large live preview (Stage 580×400 + overlays + 4 guides), right = readiness Ring(104, stroke 8, sub label) + full 6-row checklist + Re-run/Continue buttons. Header has `Skip briefing` ghost + StepTabs; no close button.

## Animated / dynamic
- `Ring value={0.83}` → 83% arc, `T.good` color (animate fill on appear).
- Pad "AI watching" chip dot pulses: `animation: st-pulse 1.4s infinite` (opacity/scale pulse keyframe).
- HeroModel renders the live subject (may have internal motion).
- `backdropFilter: blur(14px)` on the "Live preview" chip (glass).

## Implementation notes for SwiftUI
- `Ring`: needs `value` (0–1), `size`, optional `stroke`, `color`, center `label`, optional `sub` overline — build as a trimmed circle + centered text stack.
- `StatusDot` is shared shape for checklist; `pass` uses an `Ic check` with strokeWidth 2.6, warn/bad use a bold `!` glyph — keep both code paths.
- Soft status backgrounds `goodSoft/warnSoft/badSoft` pair with solid `good/warn/bad` foregrounds.
- The `st-pulse` keyframe and `backdropFilter` (glass blur) are the trickiest fidelity points — use `.symbolEffect`/opacity animation and `.ultraThinMaterial`.
- Pad layout relies on flexbox `minHeight:0` to let the checklist card scroll/clip inside a fixed column; in SwiftUI use a fixed-height container with the list allowed to compress, `overflow:hidden` ⇒ clipped (no scroll indicator).
- Inline bold within the Pad readiness body (`4.2M tris`) → AttributedString with `T.ink` color emphasis.
