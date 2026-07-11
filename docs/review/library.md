# Adversarial fidelity + bug review — Library (`LibraryScreen.swift`)

Ground truth: `docs/design-ref/screens/library.jsx` (Phone + Pad variants; Mac is out of scope for the iOS target) and `docs/design-spec/library.md`.
Implementation: `Sources/iOS/Studio/Screens/LibraryScreen.swift`.
Cross-checked APIs: `Sources/Shared/DesignSystem/{Theme,Primitives,StudioComponents}.swift`, `Sources/Shared/Studio/{StudioRender,SampleData,ScanSessionMapping}.swift`, `Sources/iOS/Studio/StudioRouter.swift`, `Sources/Shared/ProcessingStateMachine.swift` (CaptureMode raw values).

**Verdict: minor-gaps.** Structure, copy, navigation, selection state, and data wiring are faithful for both iPhone and iPad. No crashes, no broken navigation, no missing regions, no a11y gaps. Only small token/behavioral divergences remain — all P2.

---

## What is correct (both devices)

- **Copy** — all verbatim literals match: header `3DSeen · 42 scans`, title `Library`, subtitle `11.4 GB on device · 2 syncing to iCloud`, phone placeholder `Search scans, tags, materials` (no ellipsis) vs Pad `Search scans, tags, materials…` (ellipsis) — both correct and distinct. Sidebar `3DSeen` / `v2.4 · STUDIO` / `All Scans` / `Objects` / `Spaces` / `Landscapes` / `Collections` and the four collection rows (`Museum Loan` 12, `Renovation 5B` 8, `Field · Granite` 5, `Cassette Series` 9) all match, including dot colors `#9B8769 / #C58F4B / #4C5A60 / #566C70`. Filter pills `All/Object/Space/Landscape` with counts `42/28/9/5` match.
- **Navigation** — settings gear → `.settings`; phone New-Scan dock + iPad New-Scan button → `.mode`; every `ScanThumbButton` and Featured "Open in 3D" → `.viewer`; Export → `.export`; sidebar footer Settings → `.settings`. All targets exist in `StudioScreen`. No broken/wrong-screen nav.
- **Logic / crash-safety** — `LibraryData.featured` is total (`source(...).first ?? SampleData.scans[0]`, both operands always non-empty / index 0 always valid). `grid()` uses `dropFirst`/`prefix`/`filter` (all bounds-safe on empty input). All `ForEach` ids are unique (ScanItem.id, nav.key, collection.name, pill key) — no id collisions. No force-unwraps. Live `CaptureMode` raw values (`Object/Space/Landscape`) match the filter keys, so live-data filtering works.
- **a11y** — settings, search field, clear button, scan thumbs, filter pills (with `.isSelected`), sidebar nav rows (with `.isSelected`), collection rows, and footer Settings all carry explicit labels; decorative logo icon is `accessibilityHidden`. No gaps.
- **iPad is a true bespoke layout**, not a phone reflow: real `LibrarySidebar` (logo, nav, collections, storage/Settings footer) + non-scrolling rail + scrolling main with inline search + New Scan, big Featured, Recent header with right-aligned pills, 5-column grid of `SCANS.slice(1)`. Matches the Pad spec structure.

---

## iPhone

### P2 · token · Filter-pill count uses SF (monospaced-digit), not the mono face
- Ground truth: `Filters` count span is `<span className="st-num" …>` and the spec states "Mono font (`T.mono`, `.st-num`) is used for **all** counts" (library.md §Implementation notes). Every other count in this screen uses `.font(.mono(…))` (sidebar nav `.mono(11)`, collections `.mono(10.5)`, `v2.4 · STUDIO` `.mono(9.5)`).
- Code: `FilterPills.pill` renders the count as `Text("\(c)").font(.sf(11)).monospacedDigit()` — SF Pro letterforms with tabular digits, not the `T.mono` typeface. Inconsistent with the identical counts in the sidebar.
- Fix: change to `.font(.mono(11)).opacity(0.6)` to match `.st-num`.

### P2 · interaction · Filter pills + search actually filter the grid (design grid is static)
- Ground truth: the phone grid is `SCANS.slice(1, 7)` rendered unconditionally; `Filters` only swaps the selected pill's color (`onPick={setFilter}` updates highlight, the grid never reads `filter`). The search field is a static `<span>` placeholder — spec: "Search fields are non-functional placeholders … render as tappable rows."
- Code: `LibraryData.grid(...)` filters `items` by both `filter` (mode) and `query` (real `TextField` text), so tapping `Object`/`Landscape` or typing changes which thumbs appear (e.g. `Landscape` → 1 thumb).
- Assessment: this is an additive enhancement and good UX, not a defect — flagged only as an intentional divergence from the prototype to confirm intent. (Minor secondary risk: the real `TextField` raises the keyboard, which can nudge the bottom-pinned New-Scan dock via keyboard avoidance.)

---

## iPad

### P2 · token · Sidebar width is 264, should be 248
- Ground truth: `LibrarySidebar({ go, w = 248, mac = false })`; the Pad call is `<LibrarySidebar go={go} />` → **w = 248**. Only the **Mac** wrapper is `width: 264`.
- Code: `PadLibrary` sets `LibrarySidebar(filter: $filter).frame(width: 264)` — it uses the Mac rail width on iPad, making the left rail 16pt too wide and shifting the entire main column.
- Fix: `.frame(width: 248)`.

### Note (not a defect) · dual-bound filter
- The iPad sidebar nav rows and the Recent-header pills both bind the same `$filter`, so they stay in sync (tapping a Recent pill also re-highlights the sidebar row, and vice-versa). In the prototype these are independent decorative elements (`nav` buttons have no `onClick`; Recent-header `<Filters />` has no `onPick`). Unifying them is a reasonable, non-buggy interpretation of the unrecoverable/[MED] regions — listed for transparency, no action required.

---

## Reconstructed regions (ground truth unrecoverable — not scored as divergences)
`Featured` body (TAG_0/16), phone New-Scan dock (TAG_7), sidebar footer (TAG_11), and the Recent-header affordance (TAG_17) are `{{HEADROOM}}` markers with no verbatim source. The implementation's choices (Featured = thumb/HeroModel + name + stats + Open/Export; dock = accent pill in `StGlass`; footer = storage `StMeter` + Settings; Recent affordance = `FilterPills`) are all consistent with the [MED]/[LOW] reconstructions in the spec and are reasonable.
