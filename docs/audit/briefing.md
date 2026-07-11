# Audit — Scene Briefing (`briefing`)

Screen key `briefing`, Step 2 of 4. Spec: `docs/design-spec/briefing.md`, ground truth `docs/design-ref/screens/briefing.jsx`. Variants in spec: **Phone** (`PhoneBriefing`) and **Pad** (`PadBriefing`). **No Mac variant.**

Current Swift: `Sources/iOS/Studio/Screens/BriefingScreen.swift` (145 lines). It implements **only the Phone layout**; on iPad it renders the same scroll view width-capped via `readableContentWidth()`. The bespoke two-column Pad layout is entirely absent — this is the headline gap.

Supporting files referenced in fixes: `Sources/iOS/Studio/StudioChrome.swift` (WizardHeader / CircleIconButton / BottomCTA), `Sources/Shared/DesignSystem/Primitives.swift` (StRing, StButton, StCard, StChip, StRule), `Sources/Shared/DesignSystem/LiquidGlass.swift` (StGlass / `.liquidGlass`), `Sources/Shared/Studio/StudioRender.swift` (Stage, HeroModel).

---

## Phone — `PhoneBriefing`

The Phone layout is a faithful port. Remaining issues are all P2 polish.

### P2 · token · CheckRow detail is not tabular/mono
Spec marks the detail line with `className="st-num"` (`fontSize 11.5, color T.text3`), i.e. tabular figures (foundation §2: "the `.st-num` class"). Current `Text(item.detail).font(.sf(11.5))` (line 106) renders proportional digits, so values like `1842 lux`, `42 cm`, `244 GB` don't align as the design intends.
Fix: add `.monospacedDigit()` to the detail `Text` in `CheckRow`. (Note: keep SF family — only the Pad bottom caption uses true `T.mono`, the checklist detail does not.)

### P2 · token · GuideCard body line height too tight
Spec: GuideCard body `fontSize 11.5, lineHeight 1.4` (≈ +4.6 pt leading). Current uses `.lineSpacing(1.5)` (line 139), far tighter than the CSS-equivalent ~4.6 pt; multi-line bodies ("Keep angular velocity below 30 °/s…") read cramped.
Fix: `.lineSpacing(4.5)` (or compute `11.5 * 0.4`).

### P2 · token · H1 weight overshoots spec
Spec H1 `You're ready in 5 of 6`: `fontWeight 720, letterSpacing -0.9, lineHeight 1.05`. Current `.font(.sf(28, .heavy))` (line 50) is weight 800 — heavier than 720. The `lineHeight 1.05` is also unset (negligible since the title is one line).
Fix: use `.sf(28, .bold)` (700, closest standard weight to 720); optionally `.lineSpacing(1.4)` for multi-line safety.

### P2 · token · Readiness sub line height unset
Spec sub `Resolve the reflection warning to reach 100.`: `fontSize 12.5, marginTop 3, lineHeight 1.35`. Current (line 60) sets size + `text2` and relies on `VStack(spacing: 3)` for the gap but never applies the 1.35 line height. Single line today, so cosmetic.
Fix: add `.lineSpacing(4)` to the sub `Text` for wrap safety.

### P2 · token · Close icon size (shared chrome)
Spec Phone close button: `<Ic name="close" s={16} c={T.text2}/>` (16 pt). `WizardHeader` → `CircleIconButton` hardcodes `StIcon(... size: 17 ...)` for every icon (`StudioChrome.swift:15`), so close renders at 17 not 16. Back is correctly 17.
Fix: allow `CircleIconButton` to take an icon point size, or special-case close to 16.

### P2 · component · StRing track color
Foundation §3 Ring: "Track circle (color `line`)". `StRing` fills the track with `theme.fieldFillHi` (`Primitives.swift:309`). Minor and primitive-wide, but it shows on this screen's two rings.
Fix: change the track `Circle().stroke(theme.fieldFillHi…)` to `theme.line`.

### P2 · interaction · Ring fill not animated
Spec animated notes: "`Ring value={0.83}` → 83% arc … animate fill on appear." `StRing` renders a static trim. Resting state is correct (foundation §4), so this is optional polish.
Fix: drive `trim` `to:` from 0→value with `.animation(...)` on `.onAppear`.

---

## iPad — `PadBriefing` (MISSING — bespoke layout absent)

`BriefingScreen` has no `horizontalSizeClass` branch; `StudioRoot` instantiates `BriefingScreen()` for all size classes. On iPad it shows the Phone scroll layout capped to 720 pt. The spec's Pad layout is a **fixed, non-scrolling two-column** design that shares almost nothing structurally with Phone. Every item below is part of closing this gap.

### P1 · missing-ipad · Two-column Pad layout not implemented
Spec PadBriefing: `Container absolute inset:0 top:30 flex column padding:24`, then a **non-scrolling** `flex:1` body `gridTemplateColumns:'1.05fr .95fr' gap:16 minHeight:0`. Left = live preview + 4 guides; right = readiness ring card + 6-row checklist + action row. Current iPad = phone reflow only.
Fix: add a `@Environment(\.horizontalSizeClass)` branch in `BriefingScreen.body`; when `.regular`, render a new `PadBriefingBody` with an `HStack(spacing: 16)` weighted `1.05 / 0.95` (e.g. `GeometryReader` or `.frame(maxWidth:.infinity)` with `.layoutPriority`), no `ScrollView`, `.padding(24)`.

### P1 · missing-ipad · Pad header row not implemented
Spec header (`flex space-between center`): Left = back `38×38` circle (`Ic back s17 c text2` → `go('mode')`) + title stack `<Label>New Scan · Step 2 of 4</Label>` over `Scene briefing & guidance` (`fontSize 17, weight 700, ls -0.3, marginTop 2`). Center = `<StepTabs active={1} />`. Right = `<Button kind="ghost" size="sm" onClick={() => go('quality')}>Skip briefing</Button>`. Current Pad reuses the Phone `WizardHeader` (back · "Step 2 of 4" chip · close) — wrong structure, wrong copy, and it shows a Close button the Pad spec does not have.
Fix: build a dedicated Pad header HStack: `CircleIconButton(icon:"back", size:38){ model.go(.mode) }` + title `VStack { StLabel(text:"New Scan · Step 2 of 4"); Text("Scene briefing & guidance").font(.sf(17,.bold)).tracking(-0.3) }`, `Spacer`, `StepTabs(active:1)`, `Spacer`, `StButton(title:"Skip briefing", kind:.ghost, size:.sm){ model.go(.quality) }`. No close button.

### P1 · component · `StepTabs` primitive does not exist
Pad header center uses `<StepTabs active={1} />` (imported from `mode.jsx`; "Briefing" active, "Mode" done). There is no `StepTabs` view anywhere in `Sources/` (grep returns nothing).
Fix: create a shared `StepTabs(active: Int)` primitive (segmented step indicator: Mode / Briefing / Detail … with done/active/pending styling) and use it on the Pad headers of all four wizard screens (`mode/briefing/quality/compute`). Until it exists, the Pad header cannot match spec.

### P1 · missing-ipad · Left live-preview column absent
Spec left column (`flex column gap:14 minHeight:0`):
- Preview frame `flex:1 borderRadius:22 overflow:hidden boxShadow:T.cardShadow` containing `<Stage radius={22}><HeroModel w={580} h={400}/></Stage>`.
- Top-left overlay (`absolute top:14 left:14 flex gap:8`): a glass `<Chip tone="neutral" style={{background:T.glassFill, backdropFilter:'blur(14px)'}}>` `Ic camera s13` + **`Live preview`**; and `<Chip tone="accent">` with a `6×6` dot `borderRadius:99 background:T.accent animation:'st-pulse 1.4s infinite'` + **`AI watching`**.
- Bottom-left overlay (`absolute bottom:14 left:14`): `<Glass radius={14} style={{padding:'10px 14px'}}>` containing `<Label color={T.good}>Auto-detected</Label>`, **`Ceramic Vase · 14 cm`** (`16/700/-0.3`, marginTop 4), and mono caption **`conf 0.94 · 14.2 × 10.8 × 14.2 cm`** (`fontFamily T.mono, 10.5, text3, marginTop 2`).
None of this exists on the current iPad render.
Fix: build the frame with `Stage(radius: 22){ HeroModel() }` (use `Sources/Shared/Studio/StudioRender.swift`) inside a rounded clip with `cardShadow`; overlay the two chips top-left (glass chip via `StChip(tone:.neutral)` over `.liquidGlass`/`StGlass`, accent chip with a pulsing `Circle` 6×6 via `.symbolEffect`/opacity animation) and the bottom-left `StGlass(radius:14)` info card with the exact strings above (caption in `.mono(10.5)`).

### P1 · missing-ipad · Guides row shows wrong count on iPad
Spec Pad left column ends with a `gridTemplateColumns:'repeat(4,1fr)' gap:10` row of **all 4** `GUIDES` as `GuideCard`. Current iPad still renders `GUIDES.prefix(2)` in a 2-column grid (Phone slice).
Fix: in the Pad branch render all 4 guides in a 4-column `LazyVGrid` (`GuideCard` is reusable as-is).

### P1 · missing-ipad · Right readiness column absent
Spec right column (`flex column gap:14 minHeight:0`):
- Readiness card `<Card radius={22} style={{padding:20}}>` `flex gap:18 align center`: `<Ring value={0.83} size={104} stroke={8} color={T.good} label="83" sub="SCAN READY" />` + text (`flex:1`): `<Label color={T.good}>Readiness · excellent</Label>`, **`5 of 6 checks pass`** (`22/720/-0.6`, marginTop 6), and body (`13/text2/lineHeight 1.4`, marginTop 6): `Resolve the reflection warning to push fidelity to ` + **bold `4.2M tris`** (color `T.ink`) + ` with confident PBR estimation.`
- Checklist card `<Card radius={20} style={{padding:'4px 18px', flex:1, minHeight:0, overflow:'hidden'}}>` with **all 6** `CHECKLIST` rows (`Rule` between, not after last) — current iPad shows only 4.
- Action row (`flex gap:10`): `<Button kind="secondary" style={{flex:1}}>` `Ic refresh s15 c ink` + **`Re-run analysis`** (no onClick); `<Button kind="accent" style={{flex:2}} onClick={() => go('quality')}>` `Ic bolt s17 c onAccent` + **`Continue to Detail`**.
Current iPad has the single pinned `BottomCTA` "Continue to Detail" only.
Fix: build the right column with `StCard(radius:22, pad:20)` + `StRing(value:0.83, size:104, stroke:8, color:theme.good, label:"83", sub:"SCAN READY")` (primitive already supports `sub`/`stroke`); the readiness `Text` with an `AttributedString` bolding `4.2M tris` in `theme.ink`; a `StCard(radius:20)` with `.padding(.horizontal,18).padding(.vertical,4)` listing **all 6** `CHECKLIST` rows with `StRule()` between; and an `HStack(spacing:10)` of `StButton(.secondary, icon:"refresh"){}` (weight 1) and `StButton(.accent, icon:"bolt"){ model.go(.quality) }` (weight 2) using `.frame(maxWidth:.infinity)` + `.layoutPriority`.

### P1 · copy · Pad-only strings missing verbatim
Because the Pad layout is absent, every Pad-specific string is missing. Implement exactly: `New Scan · Step 2 of 4`, `Scene briefing & guidance`, `Skip briefing`, `Live preview`, `AI watching`, `Auto-detected`, `Ceramic Vase · 14 cm`, `conf 0.94 · 14.2 × 10.8 × 14.2 cm`, `Readiness · excellent`, `5 of 6 checks pass`, `Resolve the reflection warning to push fidelity to 4.2M tris with confident PBR estimation.`, `Re-run analysis`, `Continue to Detail`.

### P1 · interaction · Pad-only controls missing
Spec adds two interactions not present on iPad today: **Skip briefing** ghost button (`→ go('quality')`) and **Re-run analysis** secondary button (placeholder, no handler in spec). The Pad spec also **omits the close button** that the current `WizardHeader` always shows.
Fix: wire `Skip briefing` → `model.go(.quality)`; render `Re-run analysis` with an empty/no-op action (or hook to a future re-analysis path); drop the close button in the Pad header.

---

## Wiring

### P2 · wiring · Checklist/preview values are static mock
`CHECKLIST` and the Pad auto-detect card are hardcoded literals (lux, distance, thermal, storage, dimensions, confidence). Per project memory the capture engine is real (ARKit/RoomPlan/AutoPilot). At minimum `thermal` (`ProcessInfo.processInfo.thermalState`) and `storage` (`FileManager` volume capacity) are trivially live on-device; lighting/distance can come from the ARKit session light estimate / depth.
Fix: source the briefing checklist from real device telemetry where available, falling back to the spec copy for the demo values that have no sensor.
