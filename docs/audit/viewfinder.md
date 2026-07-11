# Viewfinder — fidelity audit

Spec: `docs/design-spec/viewfinder.md` · Ground truth: `docs/design-ref/screens/viewfinder.jsx`
Current: `Sources/iOS/Studio/Screens/ViewfinderScreen.swift`
Shared: `Sources/Shared/Studio/StudioRender.swift` (`CoverageSphere`, `Spark`, `Histogram`, `FrameStrip`), `Sources/Shared/DesignSystem/{LiquidGlass,Primitives,Theme}.swift`, `Sources/iOS/Studio/StudioRouter.swift`

## Verdict

The **iPhone** port is high-fidelity on copy, tokens and the dark-glass HUD content (top bar, telemetry capsule, coverage tile, object label, hint pill, shutter dock all match `viewfinder.jsx` strings and styling). The two real gaps on phone are (a) the design is an **absolutely-positioned overlay stack** but the Swift uses a single top-anchored `VStack` + `Spacer()`, which mis-places the object label (it should sit under the AR box at y≈560, not floated above the dock), and (b) the always-dark camera feed has no handling for the **system status bar tint**, so in Light theme the status clock renders dark-on-dark. The **iPad** variant is **entirely missing** — `StudioRoot` renders the same `ViewfinderScreen()` for every size class, so iPad gets the reflowed phone layout instead of the bespoke top-bar + dual side-rail + bottom-dock HUD the spec calls for. Notably the three render helpers the iPad needs (`Spark`, `Histogram`, `FrameStrip`) already exist but are referenced by no screen. No Mac variant exists in the spec (`Exports (no Mac variant)`), so none is expected.

> Note on a source conflict the implementer should NOT "fix": for the phone dock the spec prose says the Mode sub-line `"FULL · 4K"` is "white-50%", but the JSX ground truth (`viewfinder.jsx:135`) sets `color: '#E7B24C'` (amber). The Swift already uses amber `#E7B24C`, which is correct per the ground-truth source.

---

## iPad (P1 — bespoke layout absent)

### [P1] missing-ipad — `PadViewfinder` not implemented at all
- **Spec** (`viewfinder.md` §PadViewfinder / `viewfinder.jsx:150`): the iPad (1194×834) "spreads the HUD into a **top bar + two side rails + a bottom dock**", a fundamentally different composition from the phone's stacked clusters.
- **Current**: `StudioRouter.swift:67` maps `.viewfinder → ViewfinderScreen()` unconditionally; `ViewfinderScreen.swift` has **no** `horizontalSizeClass` branch (`grep` confirms none). iPad therefore renders the compact phone stack.
- **Fix**: add a `PadViewfinderScreen` (or a `hSize == .regular` branch inside `ViewfinderScreen`) built as a `ZStack` overlay over `CameraFeed(vb: 1194×834)` + `ARBox(box: [472,222,722,648], dim: "18.4 cm")`, with the four regions below. Promote the phone helpers (`CameraFeed`, `ARBox`, `DLabel`, `DarkTelemetry`, `Shutter`) so both layouts reuse them.

The following sub-regions all need building (each is currently 100% absent):

- **[P1] layout — Top bar (top 38, sides 20, h 46).** `Close` glass 46×46 r14 → `go('briefing')`; REC capsule r14 with dot 8×8, `"REC"` mono 12/700, `"00:42.318"` mono 13/600, a `0.5px`×18 divider `rgba(255,255,255,0.22)`, and `"OBJECT · FULL · 4096²"` mono 11 white-70%; `Spacer`; then a 4-cell telemetry strip r14 mapping `[['THERMAL','34°C','thermal'],['LIGHT','1840 lx','light'],['BATTERY','78%','battery'],['STORAGE','244 GB','download']]` (row icon s11 white-55% + key mono 8 white-50% ls1, over value mono 13/600 white, hairline `0.5px` left border for i>0).
- **[P1] layout — Left rail (top 100, left 20, bottom 158, width 252, column gap 10).** Card 1: Coverage glass r18 pad16 with `DLabel "Coverage"`, `CoverageSphere(size: 184)`, big `72%` (`44/720` ls −1.6, `%` 18 white-50%) + legend `16 strong #7FD9A6 / 3 weak #E7B24C / 3 gap #FF8A7E` (12/600). Card 2: `DLabel "Surface guidance"` over rows `[['Underside','tilt −25°','#E7B24C'],['Back-left','cw 15°','#E7B24C'],['Crown','lift camera','#FF8A7E']]` (dot 7×7 + label 13.5 white-85% + mono 11 value tinted by `c`). `CoverageSphere` already accepts a size via `.frame`, so it scales.
- **[P1] layout / wiring — Right rail (top 100, right 20, bottom 158, width 272, column gap 10).** Card 1: `DLabel "Live frame · 0247"`, `38.7` (26/720 ls −0.8) + `"dB PSNR"` 12 white-50% baseline-aligned, and `Spark(values: [33,34,32,35,36,37,38,38.7,38.5,38.4,38.7,38.6], w:104, h:34, color:"#9FC0FF")`; `0.5px` divider margin 14; 4-col grid `[['SHARP','0.94'],['PARALLAX','8.4°'],['DIST','42cm'],['FOCUS','0.99']]` (key mono 8.5 white-50% ls0.6 / value mono 13.5/600). Card 2 (histogram): `DLabel "RGB · luma"` + `"μ118 · σ42"` mono 10 white-45%, `Histogram(w:236,h:64)`, and an axis row `0 / 64 / 128 / 192 / 255` mono 8.5 white-40%. `Spark` and `Histogram` already exist in `StudioRender.swift` — wire them here.
- **[P1] layout / wiring — Bottom dock (bottom 20, sides 20, h 126, row gap 10).** Panel A `DLabel(#9FC0FF) "AI scene · Auto-Pilot"` + `"Ceramic bust"` 22/700 ls −0.5 + dims mono 10.5 white-55% `"14.2 × 10.8 × 14.2 cm · conf 0.94"` (width 252). Panel B `DLabel "Frame strip · recent"` + `kept 242` (`#7FD9A6`) · `rej 6` (`#FF8A7E`) mono 10, and `FrameStrip(count:16, sel:13, h:48)` (already exists, unused). Panel C ETA/Shutter (width 252): `Shutter(size: 84)` `flex 1` centered → `go('review')`, right block `DLabel "ETA · Mac"` + `"1:52"` (26/720 ls −1) + `"local 6:42"` mono 10 white-50%.
- **[P2] component — PadStatusBar.** Spec uses `PadStatusBar tone="light" left="9:41 · Object · 248 / 340 fr · 00:42.3"`. No equivalent exists; on a real iPad this maps to the system status bar (see status-bar finding below) plus an optional in-HUD context line. Decide whether to render a faux context label or rely on system chrome.

---

## iPhone

### [P1] layout — overlay should be absolutely positioned, not a flow `VStack`
- **Spec** (`viewfinder.md` §"Implementation notes": *"Absolute layout, no scroll: everything is pinned with explicit insets — use a ZStack with `.position`/`.padding` … Nothing scrolls; nothing should clip"*). Region D (object label) is pinned at **top 560, left 16** — i.e. directly under the AR box (`box y2 = 548`). Region C (coverage tile) is pinned at **top 166, right 16**.
- **Current** (`ViewfinderScreen.swift:156-235`): a single `VStack(spacing:0)` holds top bar → telemetry → coverage tile → `Spacer()` → object label → toast → dock. Because the object label follows a `Spacer()`, it is pushed to just above the bottom dock instead of resting under the AR box at y≈560. The coverage tile uses `.padding(.top, 8)` (≈8 gap) where the spec gap (top 106 telemetry → top 166 tile, minus tile height) is ≈17.
- **Fix**: restructure as a `ZStack(alignment: .topLeading)` over the feed and pin each cluster with `.position`/`.offset` from the top-leading origin (or `.frame(maxWidth/Height:.infinity, alignment:)` + `.padding`): top bar inset 58/16, telemetry top 106, coverage tile top 166 trailing width 132, **object label top 560 leading**, dock pinned to the bottom (bottom 28). This removes the `Spacer()` coupling and matches the design's fixed overlay.

### [P1] a11y — system status bar tint over the permanently-dark feed
- **Spec**: both variants render `StatusBar tone="light"` / `PadStatusBar tone="light"` — i.e. **white** status content because the feed is dark.
- **Current**: `ViewfinderScreen` sets no status-bar style; `StudioRoot.swift:59` applies `.preferredColorScheme(model.dark ? .dark : .light)` globally. In **Light** theme the status bar clock/icons render dark-on-dark over the camera feed (illegible). There is no `StatusBar`/`PadStatusBar` type in the codebase.
- **Fix**: force light status-bar content while this screen is up — e.g. apply `.preferredColorScheme(.dark)` (or `.colorScheme(.dark)` + `.toolbarColorScheme(.dark)`) to `ViewfinderScreen`'s root, independent of the app theme, since the feed is always dark.

### [P1] wiring / deadcode — HUD is fully static; the live render helpers it needs are orphaned
- **Spec** §"Dynamic / animated": coverage %/counts, PSNR sparkline, frame strip, REC timecode and ETA are **live readouts** in the shipping app. `Spark`, `Histogram`, `FrameStrip` exist precisely for this screen's iPad rails/dock.
- **Current**: every value is a literal (`"1840"`, `"42cm"`, `"0.94"`, `"34°/s"`, `pct: 72`, `"00:42.3"`, `"1:52"`); `grep` shows `Spark(`, `Histogram(`, `FrameStrip(` are referenced by **no screen** (dead code per `current-impl-map.md:93-95`). The wizard `ViewfinderScreen` also never shows a real feed — the real capture path is the separate `CaptureCoordinatorView`, only reachable from ModePicker's "Skip walkthrough" (`current-impl-map.md:159`).
- **Fix**: acceptable to keep literals for a static port, but (1) consume `Spark`/`Histogram`/`FrameStrip` when building the iPad layout (resolves the dead-code flag), and (2) back the telemetry/coverage/timecode/ETA with the capture model when wiring the real feed.

### [P2] interaction/animation — REC dot does not pulse
- **Spec** (`viewfinder.jsx:87`): `animation: 'st-pulse 1.4s infinite'` on the 7×7 record dot; foundation §4 defines `st-pulse` (opacity .5↔1) for the REC dot.
- **Current** (`ViewfinderScreen.swift:164`): `Circle().fill(theme.bad).frame(width:7,height:7)` — static, no animation.
- **Fix**: add a repeating opacity (and/or scale) animation: `@State private var pulse` driven by `.animation(.easeInOut(duration:1.4).repeatForever(autoreverses:true))`, oscillating opacity 0.5→1.

### [P2] token — record red is theme-dependent over a theme-independent feed
- **Spec**: `T.bad` = record red; the feed is always dark. Foundation §1 `bad` = `#FF6B5E` (dark) / `#C53B30` (light).
- **Current** (`ViewfinderScreen.swift:164`, `Shutter` line 136): REC dot and shutter swatch use `theme.bad`. In **Light** theme that resolves to the muddier `#C53B30` over the dark feed instead of the vivid dark-mode `#FF6B5E`.
- **Fix**: use the dark-mode red constant (or a fixed `Color(hex:"#FF6B5E")`) for dark-feed accents so the record indicator stays vivid regardless of app theme.

### [P2] layout — `CoverageSphere` not constrained square on phone
- **Spec** (`viewfinder.jsx:105`): `<CoverageSphere size={104} />` centered → 104×104.
- **Current** (`ViewfinderScreen.swift:246`): `CoverageSphere(pct:72).frame(height:104)` — width is unconstrained, so the `Canvas` stretches to the tile's inner width (~108) and is not centered as a square.
- **Fix**: `.frame(width:104,height:104)` and center it (`HStack { Spacer(); … ; Spacer() }` or `.frame(maxWidth:.infinity)`).

### [P2] token — heavy display weights (720) approximated inconsistently
- **Spec**: coverage `72` and ETA `1:52` are both weight **720** (`viewfinder.jsx:107,140`).
- **Current**: coverage `72` uses `.sf(30,.heavy)` (≈800) while ETA `1:52` uses `.sf(20,.bold)` (700) — the same 720 token maps to two different weights.
- **Fix**: pick one consistent mapping for 720-weight display numerals (e.g. `.heavy` everywhere, or a custom `Font.Weight(720/1000)` equivalent) so the two readouts match.

### [P2] token — warm key-light gradient not clipped to left 60%
- **Spec** (`viewfinder.jsx:10` / `viewfinder.md` impl note): the second feed gradient is `width: '60%'`, `mixBlendMode: screen` — a left-side key light.
- **Current** (`ViewfinderScreen.swift:15-17`): the `RadialGradient` is applied full-frame with `.blendMode(.screen)` and no left-60% clip; relies on radial falloff to approximate.
- **Fix**: clip the warm gradient to the left 60% of the frame (e.g. an overlay sized `width * 0.6`, leading-aligned) before `.blendMode(.screen)`.

### [P2] a11y — Close button has no VoiceOver label
- **Current** (`ViewfinderScreen.swift:159-162`): the `Button` wrapping `StIcon(name:"close")` sets no `accessibilityLabel` (only `Shutter` does, line 140).
- **Fix**: add `.accessibilityLabel("Close")` to the close button.

### [P2] layout — top-bar inset slightly over-padded
- **Spec**: top bar at **top 58** (just below the status bar).
- **Current** (`ViewfinderScreen.swift:234`): `.padding(.top, 8)` on top of the safe-area inset (~59 on notched phones) puts the bar at ~67.
- **Fix**: pin the top bar to the safe-area top (drop the extra `.top, 8`, or use `.position`/explicit inset 58 in the absolute-layout refactor above).
