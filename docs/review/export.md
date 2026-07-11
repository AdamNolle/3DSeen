# Export & Share — fidelity + bug review

Reviewed: `Sources/iOS/Studio/Screens/ExportScreen.swift` against ground truth
`docs/design-ref/screens/export.jsx` (Phone + Pad variants), spec `docs/design-spec/export.md`,
data `docs/design-ref/data.jsx` ↔ `Sources/Shared/Studio/SampleData.swift`.

**Verdict: minor-gaps.** The screen is a faithful, bespoke port. State machine, data tables,
format/option slicing, nav targets, and both device chromes match the design. No P0/P1 crash, nav,
or wrong-screen issues. A handful of small additive/token divergences only.

Verified clean:
- `EXPORT_FORMATS` (6 rows: usdz/usd/glb/obj/fbx/ply, exact name/ext/size/desc/best) match `data.jsx` verbatim.
- `DESTINATIONS` (air/AirDrop, mac/Adam's MBP, icloud/iCloud, files/Files) and icons match.
- `EXPORT_OPTIONS` (4 rows, defaults ON/OFF/ON/ON) match.
- State machine: initial `config`, `fmt='usdz'`, `dest='air'`, 180 ms timer, +3–12/tick, clamp 100,
  360 ms → done, reset. Matches.
- iPhone slices to first 3 formats + first 2 options; iPad shows all 6 + all 4. Correct.
- Nav: close → `viewer`, Done → `library`, CTA → `start()`. Correct.
- iPad is a true bespoke two-pane (left preview+stats+dest, right formats+options+CTA), not a reflow.
- Progress phase gating (<40 / <75 / else, ext appended only in final phase), `size.split(' ')[0]`,
  borderTop-except-first option dividers — all faithful.
- Timers use `[weak self]` + `deinit` invalidate; all `.first{}??[0]` lookups are bounds-safe;
  ForEach ids unique; interactive controls have a11y labels + selected traits. No crash/retain risk.

---

## iPhone (`PhoneExport`)

### P2 — layout — DoneView shows controls/text absent from ground truth
Ground truth `DoneView` (export.jsx:99–115) has exactly: success badge, "Export complete", the mono
sub-line, and two buttons ("Export again" / "Done"). The Swift `DoneView` additionally renders, when
`exportedURL != nil`: a third **"Share file"** ghost button and a mono **"<file> written"** line (and
an error line on failure). These are real-engine additions, not in the design.
Fix: this is intentional `ModelExporter` integration; if strict fidelity is required, gate these behind
a debug flag or drop them. Otherwise acceptable — flagged only as a ground-truth divergence.

### P2 — token — DestRow label weight lighter than design
`export.jsx:75`: `fontWeight: on ? 650 : 500`. Swift (`DestRow`, ExportScreen.swift:438):
`.sf(11.5, on ? .semibold : .regular)` → unselected is `.regular` (400) vs design **500 (medium)**
(selected 600 vs 650 is acceptable). Unselected destination labels render a touch lighter than spec.
Fix: use `on ? .semibold : .medium`. (Applies to both devices.)

Everything else on iPhone matches: backdrop Stage+dim (0.45 dark / rgba(20,20,30,0.28) light), grabber
38×5 lineStrong, header (ModelBadge 50, "Export Celestial Bust" 17/700/-0.3, "FULL · 4.2M tris · 184 MB"
mono 11/text3, 32×32 close → viewer), "Send to"/DestRow, "Format"/3 rows, 2 toggles, CTA → start.

---

## iPad (`PadExport`)

### P2 — layout — right-pane CTA not pinned to bottom (missing flex spacer)
`export.jsx:221–224`: right column ends with `<div style={{flex:1}}/>` then the CTA, pinning Export to
the bottom of the pane. Swift `rightColumn` (ExportScreen.swift:319–341) is a `ScrollView { VStack }`
with the CTA following the options via `.padding(.top, 22)` and no spacer, so when the content is
shorter than `bodyH` the CTA sits directly under the options instead of at the pane bottom. Impact is
small (with all 6 formats + 4 options the content usually overflows `bodyH` and scrolls, so the CTA
lands at the bottom anyway), but on taller iPads the gap can show.
Fix: add a `Spacer(minLength: 0)` before the CTA, or pin the CTA outside the ScrollView.

### P2 — layout — DoneView additions (same as iPhone)
The extra "Share file" button / "written" / error text also appear in the iPad `big` DoneView. Same note.

### P2 — token — DestRow label weight (same as iPhone)
Same `.regular` vs design 500 on the left-column destination row.

Everything else on iPad matches: backdrop+dim (0.5 / rgba(20,20,30,0.32)), centered `Glass radius 26`
width 880 padding 0 overflow-hidden, header (ModelBadge 44, "Export & Share", "CELESTIAL BUST · FULL ·
184 MB", 34×34 close → viewer, bottom rule), 2-pane config: left preview (Stage 18 + "AR Quick Look
ready" accent chip) + 4-up stats (Format/Size+MB/Tris 4.2M/Tex 4K) + "Send to"/DestRow, right
"Format" all 6 + "Options" all 4 (internal dividers only) + CTA; progress/done centered `big`.

---

## Notes (not findings)
- The local `private struct ProgressView` shadows SwiftUI's `ProgressView`; resolves to the local type
  in-file and compiles fine — no bug, just a name clash to be aware of.
- iPad `bodyHeight = max(420, min(screenH-160, 760))` keeps the modal within 11"/12.9"/mini bounds in
  both orientations; no vertical clipping observed.
