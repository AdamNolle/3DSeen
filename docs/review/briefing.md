# Review — Scene Briefing (`briefing` screen)

Ground truth: `docs/design-ref/screens/briefing.jsx` (Phone + Pad variants) and `docs/design-spec/briefing.md`.
Implementation: `Sources/iOS/Studio/Screens/BriefingScreen.swift`.

Verdict: **minor-gaps**. Copy, navigation targets, the iPad bespoke two‑column layout, tokens, and
the shared sub‑components are faithful. The iPhone variant, however, renders the **wrong slice of the
data sets** — it shows all 6 checklist rows and all 4 guides where the design shows only the first 4
and first 2 respectively. No crash/nav bugs found.

---

## iPhone (`PhoneBriefingBody`)

### P1 · layout / missing-region — checklist shows all 6 rows; design shows first 4 only
- **Ground truth** (`briefing.jsx` PhoneBriefing): `CHECKLIST.slice(0, 4).map((c, i) => (… {i < 3 && <Rule />} …))`.
  Spec: *"Phone shows `CHECKLIST.slice(0,4)` (first 4). Pad shows all 6."*
- **Code** (`BriefingScreen.swift:91–99`): iterates the full array —
  `ForEach(Array(CHECKLIST.enumerated()), id: \.element.id) { i, c in CheckRow(item: c); if i < CHECKLIST.count - 1 { StRule() } }`,
  with the author comment literally reading `// checklist (all six rows)`.
- **Effect:** the phone briefing card renders two extra rows (`Device thermal`, `Storage available`)
  that the design intentionally hides on the compact layout, lengthening the scroll body.
- **Fix:** slice to the first four on phone: iterate `CHECKLIST.prefix(4)` and gate the rule with
  `if i < 3 { StRule() }` (keep the full array only in `PadBriefingBody`).

### P1 · layout / missing-region — pro‑tips grid shows all 4 guides; design shows first 2 only
- **Ground truth** (PhoneBriefing): `GUIDES.slice(0, 2).map(g => <GuideCard … />)` inside a `1fr 1fr` grid.
  Spec: *"Phone shows `GUIDES.slice(0,2)`. Pad shows all 4."*
- **Code** (`BriefingScreen.swift:106–109`): `ForEach(GUIDES, id: \.id) { g in GuideCard(guide: g) }` in a
  two‑column `LazyVGrid`, comment `// pro-tip guides (all four)`.
- **Effect:** phone shows a 2×2 grid (4 cards: adds `Hands-free turntable`, `Avoid shiny + clear`)
  instead of the single row of 2 the design specifies.
- **Fix:** `ForEach(GUIDES.prefix(2)) { … }` (or `Array(GUIDES.prefix(2))`) in the phone grid only.

### P2 · a11y — checklist pass/warn status is not announced
- The `reflect` row is a **warn** in the design (amber dot + `!`). In `CheckRow`
  (`BriefingScreen.swift:316–332`) the `StatusDot` is `accessibilityHidden(true)` and the trailing icon is
  hidden, so the combined VoiceOver label is just `label + detail` with no indication that the row is a
  warning vs. a pass. Affects both devices (shared `CheckRow`).
- **Fix:** add a status hint to the combined element, e.g. `.accessibilityValue(item.status == "warn" ? "Warning" : "Passed")`.

---

## iPad (`PadBriefingBody`)

Faithful. Verified region‑by‑region against `PadBriefing`:
- Header: back (38) → `go(.mode)`; `New Scan · Step 2 of 4` overline + `Scene briefing & guidance` (17/bold/‑0.3);
  `StStepTabs(current: 1)` (Mode done, Briefing active); `Skip briefing` ghost/sm → `go(.quality)`. ✓
- Split ratio `1.05/2.0` matches `1.05fr .95fr`; gap 16; 18pt gap acts as the `marginTop:18`. ✓
- Left: `Stage(radius:22)`/`HeroModel`, top overlay = glass `Live preview` chip (camera 13 / text2 / `liquidGlass`)
  + accent `AI watching` chip with a pulsing 6×6 dot (0.7s autoreverse ≈ 1.4s `st-pulse`); bottom `StGlass(14)`
  with `Auto-detected` / `Ceramic Vase · 14 cm` / mono `conf 0.94 · 14.2 × 10.8 × 14.2 cm`; **all 4** guides. ✓
- Right: readiness `StRing(0.83, 104, stroke 8, "83", sub "SCAN READY")`, `Readiness · excellent`,
  `5 of 6 checks pass` (22/720/‑0.6), inline‑bold `4.2M tris` AttributedString; **all 6** checklist rows;
  action row `Re-run analysis` (secondary, no action) flex‑1 + `Continue to Detail` (accent, bolt) flex‑2 → `go(.quality)`. ✓

### P2 · token — leading button icon rendered at text size, not the design's `17`
- Design CTAs use `<Ic name="bolt" s={17} …>` (and Re‑run `refresh s={15}`). `StButton`
  (`Primitives.swift:118`) always renders the leading icon at `fontSize` (lg→16, md→15), so the bolt glyph
  is ~1–2px smaller than `17` on both the phone CTA and the iPad Continue button. Systemic to `StButton`;
  cosmetic. Fix only if pixel‑exact icon sizing is desired (add an explicit icon‑size override to `StButton`).

---

## Checked and OK (no issue)
- All literal copy matches the JSX exactly (checklist labels/details, guide titles/bodies, headings, captions,
  including `—`, `°`, `·`, `×`).
- Navigation: back→`mode`, close→`library`, Continue/Skip→`quality` — all valid `StudioScreen` cases.
- `ForEach` ids unique (`CheckItem.id`, `GuideItem.id == title`); no id collisions.
- No force‑unwraps, out‑of‑range indices, or retain cycles; `@State pulsing` declared and driven in `onAppear`.
- `StatusDot` keeps both code paths (check vs bold `!`) with correct `good/warn` + soft backgrounds.
- `actionRow` GeometryReader width math is `max(0, …)`‑guarded.
- Phone scroll bottom padding 120 vs design 110, and title weight `.bold` vs 720 — negligible, not flagged.
