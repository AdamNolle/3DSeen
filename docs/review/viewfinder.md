# Viewfinder — adversarial fidelity + bug review

Ground truth: `docs/design-ref/screens/viewfinder.jsx` (Phone + Pad)
Spec: `docs/design-spec/viewfinder.md`
Implementation: `Sources/iOS/Studio/Screens/ViewfinderScreen.swift`

**Verdict: minor-gaps.** The port is unusually faithful. Every literal string, telemetry
value, color token, font size/weight, radius, and inset I checked matches the JSX on both
devices. Navigation is correct (close → `briefing`, shutter → `review`, both routes exist in
`StudioRouter`). No crash/force-unwrap/out-of-range/id-collision issues. Layout uses
safe-area-inset compensation so the absolute design coords (top 58/106/166, bottom 28; iPad
top 38/100, bottom 158/20) land correctly across devices. Only P2 polish nits below.

---

## iPhone

### P2 · token — Shutter inner record swatch is inset further than the design
- Ground truth: `Shutter` button `padding: 5`; inner red div is `width/height 100%` of the
  padded area (inset 5 from the white edge), `borderRadius 9`, `background T.bad`.
- Code (`Shutter`, lines 176–178): inner `RoundedRectangle(cornerRadius: 9).fill(VFColor.red).padding(7)`
  — inset 7, not 5. At size 74 the red square renders ~60×60 instead of ~64×64 (and again on
  the iPad size-84 shutter, ~70 vs ~74).
- Fix: change `.padding(7)` → `.padding(5)`.

### P2 · token — AR caliper dimension label is dimmed
- Ground truth (`ARBox`): the dim text sits in `<g … fill={a}>` with `a = accent = '#fff'`, so
  `"14.2 cm"` renders at full-opacity white (`strokeWidth="0"`).
- Code (line 116): `Text(dim) … .foregroundColor(.white.opacity(0.85))` — 85% white.
- Fix: use `.white` (or keep 0.85 if intentional; the brackets themselves are full white).

Everything else on iPhone matches: top bar (close 40×40 r13 → briefing, REC capsule `00:42.3`
+ `OBJ · FULL · 4K`, thermal `34°`), telemetry `[LUX 1840 · DIST 42cm · SHARP 0.94 (green) ·
MOTION 34°/s (amber)]`, coverage tile (`Coverage` / `22 SH`, sphere 104, `72%`, `16 strong /
3 weak / 3 gap`), object label (`AI Scene · Auto-Pilot`, `Ceramic bust`, `14.2 × 10.8 × 14.2
cm · conf 0.94`), hint pill (`Slow down · 34 → under 30°/s`), and dock (Mode/Object/FULL · 4K,
shutter → review, ETA · Mac `1:52` / `local 6:42`). Close + Capture have a11y labels.

---

## iPad

### P2 · missing-region — frame-progress readout from the faux status bar is dropped
- Ground truth (line 155): `<PadStatusBar tone="light" left="9:41 · Object · 248 / 340 fr ·
  00:42.3" />`. Unlike every other screen's `PadStatusBar`, this one carries bespoke scan
  metadata — notably the frame counter **`248 / 340 fr`**.
- Code: `PadViewfinderLayout` relies on the real device status bar (via
  `.preferredColorScheme(.dark)`) and never renders this text. The REC capsule shows
  `00:42.318` and `OBJECT · FULL · 4096²` but no `248 / 340 fr`, so that progress count appears
  nowhere in the iPad HUD.
- Severity is low because a faux web status bar is normally replaced by the system status bar;
  but the frame-progress datum is unique to this screen and is genuinely lost.
- Fix: surface `248 / 340 fr` somewhere in the iPad top bar (e.g. append a divider + frame
  count to the REC capsule).

### P2 · token — Shutter inner swatch (same as iPhone)
- The iPad shutter uses the same `Shutter` component, so the `padding(7)` vs design `5` inset
  applies to the size-84 shutter too. Fixed by the single `Shutter` change above.

Everything else on iPad matches the bespoke layout (not a reflow): top bar (close 46×46 r14 →
briefing; REC capsule with `00:42.318`, 0.5px divider, `OBJECT · FULL · 4096²`; 4-cell
telemetry strip `THERMAL 34°C / LIGHT 1840 lx / BATTERY 78% / STORAGE 244 GB` with matching
icons + hairline dividers). Left rail = coverage card (sphere 184, `72%`, legend) + surface
guidance (`Underside tilt −25°` amber, `Back-left cw 15°` amber, `Crown lift camera` coral).
Right rail = PSNR card (`Live frame · 0247`, `38.7 dB PSNR`, Spark `[33,34,32,35,36,37,38,
38.7,38.5,38.4,38.7,38.6]` accent, 4-col `SHARP 0.94 / PARALLAX 8.4° / DIST 42cm / FOCUS
0.99`) + histogram card (`RGB · luma`, `μ118 · σ42`, axis `0/64/128/192/255`). Bottom dock =
AI scene (`Ceramic bust`, dims/conf) + frame strip (`Frame strip · recent`, `kept 242 · rej
6`, `FrameStrip(count:16, sel:13)`) + ETA/shutter (`1:52`, `local 6:42`, shutter size 84 →
review). Rail top/bottom math (`railHeight = physH − 258`, top 100, bottom 158) reproduces the
design pins and does not overlap the bottom dock.

---

## Notes (not findings)
- `ARBox` bracket arm length (`k = 20`), elbow `6`, and caliper offsets (`13/16/10`) are in
  view points (unscaled) while the box corners are scaled by `sx/sy`. On native widths
  (402 / 1194) `sx ≈ 1` so this is correct; fixed-size brackets at off-native widths are
  acceptable/intentional, not a bug.
- `ViewfinderScreen` routes on `horizontalSizeClass == .regular`. A large iPhone in landscape
  reports `.regular` and would get the iPad HUD; capture is presumably portrait-locked, so not
  flagged.
- CoverageSphere covered(16)/partial(3)/gap(3) sets are internally consistent with the
  `16 strong / 3 weak / 3 gap` legend.
