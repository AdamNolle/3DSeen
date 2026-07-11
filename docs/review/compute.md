# Compute screen — fidelity & bug review

Reviewed: `Sources/iOS/Studio/Screens/ComputeScreen.swift`
Ground truth: `docs/design-ref/screens/compute.jsx` (Phone + Pad variants), spec `docs/design-spec/compute.md`.

**Verdict: minor-gaps.** The iPhone (`PhoneCompute`) and iPad (`PadCompute`, "Hub & spoke")
variants are faithful ports. All copy strings, navigation targets, selection state,
the `HandoffArc` bezier/dot math, option-card data/order (mac→local on phone, local→mac on pad),
device glyphs, the iPad streaming visualization, connection telemetry card and option grid match
the prototype. No crashes, force-unwraps, index-out-of-range, ForEach id collisions, or broken nav
were found. `COMPUTE_OPTIONS` lazy color tuples are resolved against the live theme correctly.
The Mac variant (`MacCompute`) is intentionally absent — it is a macOS-target dashboard, not part
of the iOS `compute` screen.

Only small (P2) divergences remain.

---

## iPhone — `PhoneComputeBody`

Faithful. Nav row (back→`review`, "Step 4 of 4" neutral chip, close→`library`), title block,
handoff card (phone glyph / arc `progress 0.62` / mac glyph), option stack (mac then local),
and the pinned accent CTA (icon+label switch on `sel`, both branches → `viewer`) all match.

### Findings
- **P2 · token** — Title weight. JSX `"Compute pipeline"` is `fontWeight: 720`; Swift renders
  `.font(.sf(28, .heavy))` which maps to `system weight .heavy` = **800**, heavier than design
  (720 is closer to `.bold`/700). Consistent app-wide hero-title convention, but a measurable
  divergence. Fix: use `.bold` (or a custom 720 face) for hero titles, or accept the convention.
- **P2 · token** — Close-button glyph size. JSX uses `Ic close s=16` for the X (and `back s=17`),
  but the shared `CircleIconButton` renders every icon at `StIcon size 17`, so the close glyph is
  1px larger than spec. Shared-component nit; imperceptible. Fix: allow per-icon size or pass 16 for close.

---

## iPad — `PadComputeBody` / `PadHubCard`

This is a true bespoke port of the Pad design, not a phone reflow. Verified against `PadCompute`:
header (back→`review`, two-line title, "Compute on iPad" secondary + "Hand off to Mac" accent, both
→`viewer`); hero card radius 26 / pad 28; headline "Capture here." (ink) / "Render there." (accentText)
at 42px; the full paragraph copy; connection card (green dot, peer line, Ping/Loss/Sent stats);
the three-stage streaming visualization (iPad tile pbr → glass pill "STREAMING · 58%" + arc
`progress 0.58` + AES-256/multipeer/ETA chips → Mac tile wire + hinge); and the 2-up `big` option
grid in **local, mac** order (correctly reversed vs iPhone). All copy and stats match.

### Findings
- **P2 · copy** — Apostrophe in the connection-card label. Ground truth `compute.jsx:149` is
  `Connected to “Adam's MBP”` — curly double quotes (U+201C/U+201D) but a **straight** apostrophe
  (U+0027) in "Adam's". Swift uses a curly apostrophe: `"Connected to \u{201C}Adam\u{2019}s MBP\u{201D}"`.
  One-character typographic divergence from the source. Fix: use `\u{0027}` to match exactly
  (or keep the curly form as a deliberate typographic upgrade).
- **P2 · token** — Headline weight, same as iPhone: JSX `fontWeight: 730` rendered as
  `.font(.sf(42, .heavy))` = weight 800. Closer to `.bold`. Same app-wide convention caveat.

---

## Notes (verified correct, not issues)
- `HandoffArc`: quadratic bezier `B(t)`, `lift = h*0.5`, 26 dots, `t = i/25` (no div-by-zero),
  active radius 2.6/accent vs inactive 1.6/`text3.opacity(0.5)`, dashed `2 6` guide — matches spec.
- `OptionCard` selected ring is implemented as a 1px accent border vs the JSX `0.5px border + 1px
  ring`; visually equivalent, not flagged.
- Status bars (`StatusBar`/`PadStatusBar`) are intentionally dropped in favor of the system bar +
  safe area, consistent with the rest of the ported screens.
