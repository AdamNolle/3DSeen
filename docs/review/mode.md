# Review — Capture Mode Picker (`mode` screen)

Ground truth: `docs/design-ref/screens/mode.jsx` (+ `docs/design-spec/mode.md`)
Implementation: `Sources/iOS/Studio/Screens/ModePickerScreen.swift`

Verdict: **minor-gaps** — copy, layout regions, selection state, tints, fonts, hero, live-scene
card, status footer and the 1.3fr grid weighting are all faithful on both devices. The one
substantive divergence is the primary-CTA navigation target (affects both devices); the rest is
small token polish.

---

## iPhone (`PhoneModePicker`)

### P0 · interaction — Primary CTA goes to live capture, not `briefing`
Ground truth (mode.jsx:68):
```jsx
<Button kind="accent" full size="lg" onClick={() => go('briefing')}> … </Button>
```
Code (ModePickerScreen.swift:88-91 → 147-151):
```swift
StButton(title: sel == "auto" ? "Start Auto-Pilot" : "Continue · \(selected.name)",
         kind: .accent, size: .lg, icon: selected.icon, full: true, action: startCapture)
// startCapture(): stateMachine.send(.startCapture(liveMode)); live = true  → fullScreenCover(CaptureCoordinatorView)
```
The single footer CTA opens the full-screen live camera instead of advancing to the Briefing
screen. The nav row literally reads **“Step 1 of 4”**, promising a 4-step wizard
(Mode → Briefing → Detail → Capture), yet the only forward action skips straight to Capture.
`BriefingScreen` exists and is wired in `StudioRouter` (flow includes `.briefing`), so the
designed `library → mode → briefing → quality → capture` flow is bypassed and Briefing is
orphaned from this screen. The code comment frames it as preserving a removed
“Skip walkthrough · live capture” entry point, but it repurposed the **primary** CTA to do so.
Fix: `action: { model.go(.briefing) }` (route live capture from the Capture step, not here), or
keep the live shortcut but restore the designed primary path so the wizard chrome isn’t misleading.

### P2 · token — ModeTile shadow hardcoded instead of `theme.cardShadow`
Ground truth (mode.jsx:25): `boxShadow: selected ? `0 0 0 1px ${T.accentLine}, ${T.cardShadow}` : T.cardShadow`.
Code (ModePickerScreen.swift:342): `.shadow(color: .black.opacity(0.06), radius: 10, y: 6)`.
This single light layer ≈ the *light-mode* card shadow, but `theme.cardShadow` in **dark mode** is
`black 0.42 / r17 / y12` — far heavier. Hardcoding makes the tiles render nearly flat in dark mode,
inconsistent with every other surface (`StCard` uses `.stShadow(theme.cardShadow)`).
Fix: `.stShadow(theme.cardShadow)` and overlay the accent ring only when `selected`.

### P2 · token — CTA leading icon is 16pt, spec is 18pt (shared `StButton`)
Ground truth (mode.jsx:68): `<Ic name={…} s={18} c={T.onAccent} />`.
`StButton` renders its leading icon at the button `fontSize` (16 for `.lg`; Primitives.swift:118,80),
so the CTA glyph is 2pt undersized. Shared-component limitation; needs an explicit icon-size param.

Everything else faithful: nav circles (36, back s17 / close s16, `fieldFill`), title block
(“Choose capture” / hard-break “What are you / scanning today?” 30·720·-1 / sub copy), big Auto
tile + 2×2 grid of the other 3 (4th cell left empty, no stretch), CTA copy branches on `auto`,
dock pinned bottom 28 / inset 20 (`BottomCTA`).

---

## iPad (`PadModePicker`)

### P0 · interaction — Primary CTA goes to live capture, not `briefing`
Ground truth (mode.jsx:125): `<Button kind="accent" size="lg" onClick={() => go('briefing')}> … Continue with {name}</Button>`.
Code (ModePickerScreen.swift:296-297, wired via body:72 `onContinue: startCapture`):
```swift
StButton(title: "Continue with \(selected.name)", kind: .accent, size: .lg,
         icon: selected.icon, action: onContinue)   // onContinue == startCapture
```
Same root issue as Phone: the footer CTA launches the live camera instead of `go('briefing')`.
On iPad it is more jarring because the header renders the full `StStepTabs`
(Mode · Briefing · Detail · Capture) stepper — the visible stepper implies Continue moves to
**Briefing**, but it jumps to Capture. Fix: route to `.briefing`.

### P2 · token — ModeTile shadow hardcoded (same as Phone)
The four big tiles use the same hardcoded `.shadow(0.06, r10, y6)` (ModePickerScreen.swift:342)
rather than `theme.cardShadow`; flat in dark mode. Same fix.

### P2 · token — CTA leading icon 16pt vs spec 18pt (same shared `StButton` limitation).

Everything else faithful: header (back 38 + title stack “New Scan · Step 1 of 4” / “Choose capture
mode” 17·700·-0.3, `StStepTabs(current:0)`, close 38), hero (“3DSeen · Capture engine” accentText,
“What are you scanning?” 48·-2, body copy, live-scene `StCard` 280 w / Stage 56 + HeroModel /
“Live scene” / “Object · table-top” 14·650 / mono “conf 92% · 1840 lux”), 4 big tiles with Auto at
1.3× via `unit*1.3` weighting and `fillHeight` bottom-aligning spec chips, status footer
(Device / Thermal / Storage with exact values), CTA copy always “Continue with {name}”.

---

## Logic / crash audit
No crash risks found. `STUDIO_MODES.first {…} ?? STUDIO_MODES[0]`, `STUDIO_MODES[0]`, and
`STUDIO_MODES[1...]` are all in-bounds (4 fixed elements). No force-unwraps. `ForEach(… id: \.id)`
and `id: \.self` keys are unique. Grid `unit` is clamped with `max(0, …)`. `@State`/`@Binding`
wiring is correct; `didPersist` guards the single persist. No retain cycles.

## a11y
Adequate: nav circles have Back/Close labels; tiles expose `"{name}. {tag}"` + `.isSelected`;
decorative icons/`SELECTED` chip are `accessibilityHidden`; the H1 collapses its two `Text`
lines into one label. No missing labels on interactive controls.
