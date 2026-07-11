# Audit — Capture Mode Picker (`mode`)

Spec: `docs/design-spec/mode.md` · Ground truth: `docs/design-ref/screens/mode.jsx` · Foundation: `docs/design-spec/00-foundation.md`
Swift: `Sources/iOS/Studio/Screens/ModePickerScreen.swift` (+ shared `Primitives.swift`, `StudioChrome.swift`, `StudioRender.swift`, `StudioRouter.swift`).

Verdict: the **Phone** variant is a faithful, near-complete port (data, copy, featured tile + 2×2 grid, selection visuals, branching CTA all correct). Two real gaps dominate: (1) the entire **iPad** bespoke layout (`PadModePicker`) is absent — iPad gets the phone column merely centered/capped at 720pt; the `StepTabs` stepper primitive does not exist in Swift at all; (2) several small token/component fidelity misses (SELECTED/spec chip font sizes, H1 weight/leading) plus an off-spec "Skip walkthrough" control the design never had. No Mac variant exists in the spec, so none is expected.

---

## iPad (regular size class)

### P1 — missing-ipad — `PadModePicker` bespoke layout is entirely absent
`ModePickerScreen` renders the iPhone layout for every size class; the only iPad accommodation is `.readableContentWidth()` (caps the column at 720 and centers — `StudioChrome.swift:70-86`). The spec defines a fully distinct `PadModePicker` (`mode.jsx:91-130`, spec §PAD) that shares nothing structurally with phone:
- Root is a **single non-scrolling flex column** at `top:30, padding:24` (Pad status bar), not a `ScrollView`.
- **Header row**: back `38×38` + a title stack — `<Label>New Scan · Step 1 of 4</Label>` over `Choose capture mode` (fontSize **17**, weight **700**, ls **-0.3**) — then `<StepTabs active={0}/>` centered, then close `38×38`. Current phone header is just `WizardHeader` (back · "Step 1 of 4" chip · close); no title stack, no stepper, buttons are 36 not 38.
- **Hero row** (`alignItems:flex-end; gap:20; marginTop:28; marginBottom:22`): left marketing block — `<Label color={accentText}>3DSeen · Capture engine</Label>`, H1 fontSize **48** / weight **730** / ls **-2** / lh **1** `What are you scanning?`, body fontSize **15** color text2 `Auto-Pilot uses a CoreML vision model to read the scene and pick the optimal capture mode. Or pin a specific mode for full manual control.` — and a right **Live scene card** (`Card radius=18`, width **280**): `56×56` `Stage`+`HeroModel(w:56,h:56)`, `<Label>Live scene</Label>`, `Object · table-top` (14/650), mono `conf 92% · 1840 lux` (`T.mono`, 10.5, text3). None of this exists.
- **Mode grid**: all **4** modes as `big` tiles in one row, columns `1.3fr 1fr 1fr 1fr` (Auto wider), `gap:14; flex:1; minHeight:0`. Current iPad shows the phone arrangement: one big Auto tile + a 2-col grid of the other 3.
- **Footer row**: left status group (`gap:28`) of three Label+value pairs — `Device / iPad Pro M4 · LiDAR`, `Thermal / Nominal · 31°C`, `Storage / 244.6 GB free` (value 13.5/600/ink) — and a right CTA `Continue with {selectedModeName}` (**always** this form on Pad, no Auto branch). Current footer is the phone `BottomCTA` with the branching `Start Auto-Pilot` / `Continue · {name}` label.

Fix: add a `PadModePicker` view and dispatch on `@Environment(\.horizontalSizeClass)` inside `ModePickerScreen.body` (`hSize == .regular ? AnyView(PadModePicker(...)) : AnyView(phoneBody)`), mirroring the size-class pattern already used in `LibraryScreen`. Build it as a top-aligned `VStack`/`Grid` (no `ScrollView`). Use `Grid`/`GeometryReader` weighting to realize `1.3 : 1 : 1 : 1` column widths and give the grid row a fixed/`maxHeight:.infinity` so the four `big` tiles share height. Reuse `Stage { HeroModel(...) }` for the live-scene card (radius 14), `StCard(radius:18)` for the card shell, `StLabel`, `StButton(kind:.accent,size:.lg, icon: selected.icon)` with title `"Continue with \(selected.name)"`. Status-footer values can come from real device APIs later but should at least render the three Label+value pairs.

### P1 — component — `StepTabs` stepper primitive does not exist in Swift
Spec §StepTabs (`mode.jsx:74-89`) defines `StepTabs({active})` used by the Pad header: steps `['Mode','Briefing','Detail','Capture']`, each a pill `padding:'7px 13px'; radius:10; gap:7`, bg `fieldFillHi` when `on` else transparent, text `ink/text3`, fontSize **13**, weight **650 on / 500 off**; leading `16×16` circle badge (`radius:99`, mono, fontSize **9**, weight **700**) — bg `good` if done / `accent` if on / `fieldFillHi` else, color `#fff` if done|on else `text3`, content `'✓'` if done else `i+1`. No equivalent struct exists anywhere in `Sources/` (`grep StepTabs` → 0 hits). This primitive is shared by every Pad wizard screen (mode/briefing/quality/...), so it belongs in shared chrome.

Fix: add a `StepTabs` view (in `StudioChrome.swift`) taking `active: Int` and the fixed `steps` array; render the badge with `.font(.mono(9, .bold))` and `Text(done ? "✓" : "\(i+1)")`, pill `.font(.sf(13, on ? .heavy : .medium))`. Then place it in the Pad header row.

---

## Phone (compact size class)

### P2 — layout / wiring — off-spec "Skip walkthrough · live capture" control + live-capture cover
The spec footer dock (`mode.jsx:67-69`) contains **only** the single primary `Button` (`Start Auto-Pilot` / `Continue · {name}` → `go('briefing')`). The implementation wraps the CTA in a `VStack` and adds a second tappable control below it — `StIcon("camera")` + `Text("Skip walkthrough · live capture")` — that calls `stateMachine.send(.startCapture(liveMode))` and presents a `fullScreenCover` with `CaptureCoordinatorView` (`ModePickerScreen.swift:90-128`). This control and its label exist nowhere in the design. It is the app's only live-capture entry point (intentional engine wiring per `current-impl-map.md`), so this is a deliberate deviation rather than a bug — but it is a visible fidelity gap against the spec'd footer.

Fix: decide intent. To match spec, remove the secondary button and route live capture from elsewhere (e.g. viewfinder). To keep the engine entry, treat it as a sanctioned deviation and document it; at minimum drop it from the audited "design-faithful" footer or gate it behind a debug flag. Either way, record the divergence.

### P2 — wiring — persisted `ScanSession` uses placeholder geometry values
The `.packagingScan` handler inserts a real `ScanSession` but with `sizeMB: Int.random(in: 60...260)` and `triangles: "4.2M"` hardcoded (`ModePickerScreen.swift:113-124`). Not spec'd on this screen, but the random size / fixed triangle count are mock data masquerading as real capture output.

Fix: derive `sizeMB`/`triangles` from the actual capture/packaging result once available, or mark these as TODO placeholders explicitly.

### P2 — token — H1 weight uses `.heavy` (≈800) vs spec 720
Spec phone H1: `fontWeight: 720` (`mode.jsx:59`). Impl: `.font(.sf(30, .heavy))` (`ModePickerScreen.swift:68`). SwiftUI `.heavy` is ~800 — heavier than the spec'd 720 (which sits between `.bold` 700 and `.heavy`). Consistent with the codebase's habit of mapping 7xx display weights to `.heavy`, so low-risk, but technically over-weighted.

Fix: prefer `.bold` for the closest match to 720, or introduce a custom `Font.system(size:30).weight(.init(...))` mapping if exact-ish weights matter.

### P2 — token / layout — H1 line-height 1.05 not applied
Spec H1 has `lineHeight: 1.05` on the two-line `What are you\nscanning today?` (`mode.jsx:59`); impl sets no `lineSpacing`, so the two lines render at the system's natural leading (~1.2), looser than the tight spec block (`ModePickerScreen.swift:67-68`).

Fix: tighten with `.lineSpacing(-2)` (or a negative value tuned so the 30pt lines sit at ~31.5pt) on the title `Text`.

### P2 — component — `StChip`/`StTextChip` cannot honor per-instance `fontSize`
The shared chip hardcodes `.font(.sf(12, .semibold))` (`Primitives.swift:252`) with no size override. The spec needs two smaller sizes here:
- SELECTED badge: `<Chip tone="accent" style={{fontSize:9}}>SELECTED</Chip>` — spec §ModeTile line 39 calls it "very small uppercase" (**9pt**). Impl renders it at 12 (`ModePickerScreen.swift:149`).
- Big-tile spec chips: `<Chip tone="neutral" style={{fontSize:11}}>` (`mode.jsx:39`). Impl renders at 12 (`ModePickerScreen.swift:157`).

Fix: add an optional `fontSize: CGFloat? = nil` (and matching `hPad`/`vPad`) to `StChip`/`StTextChip` and pass 9 for SELECTED and 11 for the spec chips.

### P2 — component — `ModeTile` lacks `marginTop:auto` (Spacer) before spec chips
Spec big-tile spec-chip row uses `marginTop:'auto'` (`mode.jsx:38`) so chips pin to the tile bottom when tiles share a fixed height. `ModeTile` places the chips directly after the subtitle with only `.padding(.top, 14)` and no `Spacer()` (`ModePickerScreen.swift:154-160`). Harmless on phone (the lone big Auto tile is auto-height) but it will break the iPad equal-height 4-tile row, where chips must bottom-align.

Fix: insert `if big { Spacer(minLength: 0) }` before the spec-chip `HStack` (it pushes chips down only when the tile is height-constrained).

### P2 — token — close-button icon size 16 vs impl 17
Spec nav row: back `s={17}`, close `s={16}` (`mode.jsx:53,55`). `WizardHeader` renders both via `CircleIconButton`, which hardcodes `StIcon(... size: 17 ...)` (`StudioChrome.swift:15`), so the close glyph is 1pt larger than spec. Trivial.

Fix: allow `CircleIconButton` to take an icon size (or special-case close to 16); cosmetic.

---

## Correct / no action (verified against ground truth)
- `STUDIO_MODES` data — ids, names, icons, tags, subs, specs, tints all verbatim incl. hex literals and en-dashes (`4–10 min`). (`ModePickerScreen.swift:15-28`)
- Phone copy: `Choose capture`, `What are you\nscanning today?`, `Auto-Pilot will pick for you — or choose a mode.`, CTA `Start Auto-Pilot` / `Continue · {name}` all exact. Back & Close both → `model.go(.library)`; CTA → `model.go(.briefing)`.
- Featured big Auto tile + 2×2 `LazyVGrid` of the other 3 (4th cell empty, no stretch) matches spec.
- Selection visuals: `accentSoft` bg, `accentLine` border (1pt when selected approximates the spec ring), icon-chip fill swap to `accent`/`onAccent`, inset line border when unselected, SELECTED chip tone `accent`, tile/icon radii (22/18, 14/12) and paddings (20/15) all correct.
- No Mac variant expected (spec §line 3: "No Mac variant").
