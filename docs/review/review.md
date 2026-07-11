# Review screen — adversarial fidelity + bug review

Scope: `Sources/iOS/Studio/Screens/ReviewScreen.swift` vs ground truth
`docs/design-ref/screens/review.jsx` (PhoneReview + PadReview) and `docs/design-spec/review.md`.
Shared API cross-checked against `Primitives.swift`, `StudioComponents.swift`, `StudioRender.swift`
(`CoverageDome`), `StudioChrome.swift` (`CircleIconButton`/`BottomCTA`), `SampleData.swift`
(`DROPS` → `SampleData.dropouts`), `StudioRouter.swift`.

Overall verdict: **minor-gaps**. Copy is exact on both devices; navigation, data, severity
tinting, stats, and the iPad two-column dashboard all match. One visible iPhone layout bug and a
few polish items.

Note: the stale git snapshot listing untracked `Sources/iOS/Studio/SampleData.swift` /
`StudioRender.swift` is a non-issue — those files no longer exist; the only definitions of
`SampleData`/`Dropout`/`CoverageDome` live under `Sources/Shared/Studio/`, so there is no duplicate-
type build break.

---

## iPhone (PhoneReview)

### P1 — layout — Coverage card is not full-width (hugs the dome, left-aligned)
- Ground truth (review.jsx:29): `<Card radius={22} style={{ padding:16, marginTop:14,
  display:'flex', flexDirection:'column', alignItems:'center' }}>` — a block-level card that
  spans the full scroll-body width (column has `padding:'8px 20px 110px'`), with the legend row
  (`alignSelf:'stretch', justifyContent:'center'`) and the 258px dome centered inside it.
- Code (ReviewScreen.swift:119-132): the card content is
  `VStack(spacing: 4) { HStack(legend); CoverageDome(...).frame(width: 258, height: 258) }`
  with **no** `frame(maxWidth: .infinity)`. `StCard` (Primitives.swift:50-62) has no width
  expansion, so it hugs its content (≈258 + 32 pad ≈ 290pt). The parent
  `VStack(alignment: .leading)` is driven to full column width by the greedy header (HStack with
  Spacers) and the greedy `weakSpotsCard` (rows contain `Spacer(minLength: 0)`), so the coverage
  card renders **narrower than every sibling and pinned to the left**, leaving a visible gap on
  the right. The dome/legend therefore are not centered in the column.
- Fix: add `.frame(maxWidth: .infinity)` to the coverage card's `VStack` (its default `.center`
  alignment then centers both the legend row and the dome), matching the full-width block card.

### P2 — token — Share button icon rendered 1px too large
- Ground truth (review.jsx:22): header share button `Ic name="share" s={16}` (back is `s=17`).
- Code: `CircleIconButton(icon: "share")` (ReviewScreen.swift:103) and `CircleIconButton`
  (StudioChrome.swift:54) hardcode `StIcon(name: icon, size: 17, ...)`, so the share glyph is 17
  instead of 16. Trivial; same component is reused for the iPad back (which is correctly 17).

### P2 — layout — Missing 8px top padding in scroll body
- Ground truth (review.jsx:18): scroll container `padding:'8px 20px 110px'` (8px top).
- Code (ReviewScreen.swift:63-71): the `ScrollView` `VStack` applies `.padding(.horizontal, 20)`
  and `.padding(.bottom, 110)` but no top padding. Largely masked by the safe-area inset; cosmetic.

Faithful on iPhone otherwise: header (back→`go(.viewfinder)`, centered `Capture complete` good
chip with 6px green dot, dead share button — dead in the prototype too), title block
("Coverage 92% · 340 frames" / "Review & retake" / "3 weak spots flagged. Retake them, or proceed
to compute."), legend Strong/Weak/Missing (good/warn/bad, 8px dots), numbered weak-spot rows
(`sevColor` badge at `.opacity(0.12)`, `i+1`, label/hint, per-row Retake→`go(.viewfinder)` with
`accessibilityLabel("Retake \(label)")`), `StRule` dividers, and the sticky footer with the
flex 1 : 1.5 secondary/accent split (`unit*2` / `unit*3`), Retake all→`go(.viewfinder)`,
Compute now→`go(.compute)`. a11y labels for back/share come from `CircleIconButton`'s default
`Self.label(for:)`.

---

## iPad (PadReview)

### P2 — interaction — Frame-timeline Segmented made functional (not in the design)
- Ground truth (review.jsx:138): `<Segmented size="sm" options={['All','Keep','Reject']}
  value="All" onChange={() => {}} />` — a **static, decorative** control (fixed value, no-op
  handler); the 72-cell filmstrip never changes.
- Code (ReviewScreen.swift:175, 319-324, 346-367): `@State frameFilter` is bound to the segmented
  and `frameCell` dims non-matching cells to `opacity(0.16)` when "Keep"/"Reject" is selected.
  This is added behavior beyond the prototype. It is a reasonable enhancement and harmless, but it
  diverges from the reference (where the strip is inert). Confirm it is intended; otherwise pin the
  value to "All" / make the control non-interactive to match.

The rest of the iPad dashboard is faithful: header (back size 38→`go(.viewfinder)`,
"Post-capture · Object" / "Review & retake" 17/700, inline `Retake all` secondary-sm→viewfinder
and `Compute now` accent-sm→compute); the 1.1fr/.9fr grid via `StSplitPane(ratio: 0.55, gap: 16)`
(0.55 == 1.1/(1.1+.9)); coverage hero ("Coverage map · 92%", "You almost have it." 34/heavy
tracking −1.1, the body copy verbatim with maxWidth 360, the side legend with 9px dots/gap 7,
the 400px centered dome, and the 5-up REVIEW_STATS footer with Coverage green / Rejected amber via
`colorKey` and a top `StRule`); the weak-spots card ("Weak spots — 3 flagged", per-row Skip
(ghost, no-op — dead in proto too) + Retake (secondary→viewfinder), `StRule` between rows); and
the 72-cell timeline (`LazyVGrid` 12 columns, rejected indices {14,32,33,51,60}, warm tone-pair
cycle `i % 3`, `×` glyph on rejected, footer Kept 334 / Rejected 6 / Interval 0.18s).

---

## Bug / crash-risk sweep (both devices)
- No force-unwraps, no out-of-range indices. `reviewFramePairs[i % 3]` is always in {0,1,2}.
- `ForEach(Array(SampleData.dropouts.enumerated()), id: \.element.id)` — `DROPS` ids
  (`crown`/`earl`/`under`) are unique → no id collision. `ForEach(0..<72, id: \.self)` is safe.
- `CoverageDome` pins use `id: \.element.id` and `accessibilityHidden(true)` (decorative; the
  textual weak-spot list carries the same info).
- `BottomCTA` `GeometryReader` math: `unit = (width - 8)/5` can be transiently negative pre-layout
  → `frame(width:)` clamps to 0, no crash.
- `@State frameFilter` is the only mutable state and is correctly declared.
- All navigation targets (`.viewfinder`, `.compute`) exist in `StudioScreen`; `model.go` is sound.
