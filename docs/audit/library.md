# Audit — Library / Home (`library.jsx` → `LibraryScreen.swift` + `MacLibraryPane`)

Spec: `docs/design-spec/library.md`, raw `docs/design-ref/screens/library.jsx` (26 inner spans were proxy-compressed → reconstructed; see appendix). Foundation: `docs/design-spec/00-foundation.md`.

Implementation:
- iPhone **and** iPad share one screen: `Sources/iOS/Studio/Screens/LibraryScreen.swift` (no size-class branch; routed unconditionally by `Sources/iOS/Studio/StudioRouter.swift:64`).
- macOS: `MacLibraryPane` + shared `sidebar`/toolbar inside `Sources/macOS/ContentView.swift` (`MacShell` line 41, sidebar line 64, pane line 126).

Verdict: the Phone screen is a faithful port of `PhoneLibrary` with a few token/structure deltas and one non-spec floating dock embellishment. The **iPad variant is entirely missing** (no `LibrarySidebar`, no split, no inline search+New-Scan row, no 5-col Recent grid — just the phone screen width-capped to 980 with a 4-col grid) — the single biggest gap. The **Mac** variant exists but diverges from `MacLibrary` on the sidebar (keeps a logo the spec drops, app-section nav instead of content categories, no Collections, 248 vs 264 width) and the toolbar (no 260px search box, no grid/list Segmented, primary button is a no-op "New Scan" instead of "Open" → viewer).

---

## PHONE — `PhoneLibrary` vs `LibraryScreen`

### P2 · token · Settings gear icon size 17 vs spec 18
Spec header: settings button icon `<Ic name="settings" s={18} c={T.text2} />` (TAG_2). Current: `StIcon(name: "settings", size: 17, color: theme.text2)` (LibraryScreen.swift:29). Off by 1pt.
Fix: `size: 18`.

### P2 · token · "Library" title weight overshoot
Spec: `fontWeight: 720` (LibraryScreen.swift:59 in the jsx). Current: `.font(.sf(36, .heavy))` (LibraryScreen.swift:37) — `.heavy` = 800, heavier than the spec's 720. The foundation calls 720 a "heavy display" weight between bold(700) and heavy(800).
Fix: use `.bold` (700) or a numeric weight closer to 720 (e.g. `Font.system(size: 36, weight: .bold)` then `.fontWeight(.heavy)` is too heavy — prefer `.bold`). Letter-spacing `-1.2` and top-pad 6 are correct.

### P2 · layout · Floating dock is a "Library | New Scan" segmented pill, not a single "New Scan" pill
Spec floating dock (TAG_7, [MED]): a single centered accent pill, `<Button kind="accent" size="lg" onClick={() => go('mode')}><Ic name="scan"/> New Scan</Button>`, optionally wrapped in `<Glass>`. The spec prose (library.md §Phone step 8 and Device-differences) describes it as the "floating centered 'New Scan' dock".
Current (LibraryScreen.swift:91-110): an `StGlass` capsule containing TWO segments — a non-spec `grid`-icon + "Library" label segment AND the accent "New Scan" button. The extra "Library" segment is not in the spec, and the pill height is 46 (spec `size: .lg` = 52).
Fix: drop the "Library" segment; render a single `StButton(title: "New Scan", kind: .accent, size: .lg, icon: "scan") { model.go(.mode) }` centered, optionally inside `StGlass(radius: 999)`. If a persistent bottom nav was intended, that is a product decision outside this spec — flag for design.

### P2 · layout · Live "Captured on this device" grid is inserted between Featured and Filters (extra region + reordering)
Spec order inside the scroll: header → title → subtitle → search → **Featured → Filters → 2-col grid (`SCANS.slice(1,7)`)**. There is exactly one grid.
Current (LibraryScreen.swift:60-83): when `saved` (SwiftData) is non-empty it inserts a whole extra "Captured on this device" `LazyVGrid` of live sessions **before** `FilterPills`, then still renders the sample `scans[1..<7]` grid below. Result: two stacked grids and Filters pushed down between them — structurally different from the single-grid spec.
Fix: pick one source of truth. Either drive the single spec grid from `saved` (falling back to `SampleData` when empty) keeping Featured → Filters → grid order, or keep the live section but move Filters above Featured-independent content so the spec hierarchy is preserved. Avoid showing two grids.

### P2 · wiring · Search bar is a non-tappable static label
Spec: "Search fields are non-functional placeholders (static `<span>`) — **render as tappable rows**." Current (LibraryScreen.swift:47-55) is a static `HStack` with no `Button`/`onTapGesture` and no `TextField`. Faithful as a visual mock but not even tappable, and there is no filtering pipeline.
Fix (minimum): wrap in a `Button`/`onTapGesture` so it reads as interactive. (Future: real `TextField` bound to a query that filters the grid.)

### P2 · interaction · Filter pills don't filter anything
`FilterPills` (LibraryScreen.swift:145-168) toggles `active` but nothing consumes `filter` — the grid is always `SampleData.scans[1..<7]`. (The prototype is also inert here, so this is spec-faithful, but the control implies filtering.)
Fix: filter the grid by `mode` when a non-"All" pill is active (`Object`/`Space`/`Landscape` map to `scan.mode`), or document as intentionally inert.

### P2 · wiring · Hardcoded counts diverge from the live count shown in the subtitle
Header label is hardcoded `"3DSeen · 42 scans"` (LibraryScreen.swift:26) and FilterPills counts are hardcoded `(All 42, Object 28, Space 9, Landscape 5)` (line 148), yet the subtitle switches to a live `"\(saved.count) captured on this device · synced to iCloud"` when `saved` is non-empty (lines 40-42). So with real scans the subtitle reflects reality but "42 scans" / "All 42" do not. Spec counts are literal (`counts = { All: 42, … }`), so hardcoding matches the spec — the inconsistency is introduced by the live subtitle.
Fix: either keep everything on spec literals, or derive all three (header count, subtitle, FilterPills "All") from the same live source.

### (informational) StatusBar / 54pt top reserve
Spec pins `<StatusBar />` and starts the scroll at `top:54` (prototype chrome). The real iOS app gets the system status bar from the OS and the `ScrollView` already respects the safe area, so no faux StatusBar is needed. Not a defect.

---

## IPAD — `PadLibrary` (MISSING)

### P1 · missing-ipad · No bespoke iPad layout at all — sidebar/split/5-col Recent grid absent
Spec `PadLibrary`: 30pt status bar; body `display:flex; padding:22; gap:22` with **left `<LibrarySidebar go={go} />`** (248px: logo header, 4-row category nav `All Scans 42 / Objects 28 / Spaces 9 / Landscapes 5` with active state + mono counts, `Collections` label + 4 dot rows `Museum Loan 12 / Renovation 5B 8 / Field · Granite 5 / Cassette Series 9`, spacer + footer) and a scrolling **main** containing: an inline search row (`flex:1` field height 46 + accent `New Scan` button), `Featured … big`, a `Recent` header (`fontSize 20, weight 700, ls -0.4`) with a right `<Filters />` affordance, and a `repeat(5,1fr)` grid of `SCANS.slice(1)` (all scans).
Current: iPad is routed to the same `LibraryScreen` (StudioRouter.swift:64, no `horizontalSizeClass` branch). The only adaptivity is `readableContentWidth(980)` (centers/caps width, StudioChrome.swift:70) and `AdaptiveColumns.count(hSize, compact: 2, regular: 4)` → a 4-col grid (LibraryScreen.swift:13-16). There is **no sidebar, no `LibrarySidebar` component, no Collections, no inline search+New-Scan row, no `big` Featured, no "Recent" header, and the grid is 4-wide (spec 5) over only `scans[1..<7]` (spec wants all of `slice(1)`)**.
Fix: add a regular-width branch (e.g. `if hSize == .regular { PadLibrary() }`). Build a reusable `LibrarySidebar(mac: Bool)` view (logo when `!mac`, the 4-item category nav with `T.fieldFillHi` active row, Collections list with colored dots) and compose it with a `NavigationSplitView`-style two-column body: sidebar (≈248) + scrolling main (search field height 46 + `StButton(.accent, "New Scan")` row, `FeaturedCard` in a wide/`big` layout, `Recent` header `sf(20,.bold) tracking(-0.4)` + `FilterPills`, `LazyVGrid` 5 columns over `SampleData.scans.dropFirst()`). Search placeholder on Pad is `"Search scans, tags, materials…"` (note the ellipsis, unlike Phone).

---

## MAC — `MacLibrary` vs `MacLibraryPane` (`Sources/macOS/ContentView.swift`)

### P1 · missing-mac · Toolbar missing search box, grid/list Segmented, and primary button is a no-op "New Scan" instead of "Open"
Spec toolbar (height 52, `padding 0 20`, bg `card2`, `borderBottom 0.5px line`, gap 14): `<div width:56>` traffic-light gutter → title `All Scans` (15/700/-0.3) → accessory → spacer → **search box** (`width:260; height:32; radius:9; bg fieldFill; inset 0.5px line`, leading `<Ic search s=14>` + `Search`) → **`<Segmented size="sm" options={[{grid:'◧'},{list:'☰'}]} value="grid" />`** → **`<Button kind="accent" size="sm" onClick={() => go('viewer')}><Ic open/> Open</Button>`**.
Current (ContentView.swift:133-139): title `All Scans` ✓, `StTextChip("42 items")` accessory (acceptable TAG_20), Spacer, then `StButton(title: "New Scan", kind: .accent, size: .sm, icon: "scan") {}` — **wrong label, and the action is empty `{}` (no-op)**. There is **no 260px search box, no grid/list `StSegmented`, and no 56px traffic-light gutter**.
Fix: add the leading `Color.clear.frame(width: 56)` gutter; add the search box (`HStack` w/ `magnifyingglass` + "Search", `frame(width: 260, height: 32)`, radius 9, `fieldFill` + 0.5px `line`); add `StSegmented(options: [("grid","◧"),("list","☰")], value:)` size `.sm`; change the primary button to `StButton(title: "Open", kind: .accent, size: .sm, icon: "export"or"cube") { /* open selected → viewer */ }`. (A "New Scan" CTA is not part of the Mac flow — `FLOWS.mac = library → viewer → compute → export → settings`.)

### P1 · missing-mac · Sidebar diverges from `LibrarySidebar(mac)` — keeps the logo the spec drops, uses app-section nav instead of content categories, omits Collections
Spec Mac sidebar: `width:264; bg card2; borderRight 0.5px line; padding '52px 16px 18px'` rendering `<LibrarySidebar go mac />` where **`mac=true` ⇒ NO logo header** (the 52px top inset clears the traffic lights), the nav is the 4 **content categories** `All Scans 42 / Objects 28 / Spaces 9 / Landscapes 5` (active = `All Scans`, `T.fieldFillHi` bg, leading category icon, trailing mono count), followed by a **`Collections`** label + 4 colored-dot rows (`Museum Loan 12 #9B8769 / Renovation 5B 8 #C58F4B / Field · Granite 5 #4C5A60 / Cassette Series 9 #566C70`), spacer, footer.
Current (ContentView.swift:64-118): width **248** (spec 264), `padding(.top, 40)` (spec 52), and it **keeps the logo header** (`3DSeen` + `v2.4 · STUDIO`, lines 66-74) that the spec's `mac` branch removes. The nav is `MacSection` = **app destinations** `Library/Model/Compute/Export` (lines 77-91), not the content categories with counts. **Collections is entirely missing.** Footer is a Storage `StCard` + dark-mode toggle (a reasonable, non-spec addition; the dark toggle is genuinely useful since iOS lacks one).
Fix: build the shared `LibrarySidebar(mac:)` and use it here with `mac: true` (drop logo), width 264, top inset 52. Render the 4 category rows with mono counts and the `Collections` list with dot colors. If app-level destination switching is still required on Mac, keep it as a separate top section or move it into a toolbar/`TabView`, but the spec's primary sidebar content is categories + collections. (At minimum: bump width 248→264, top pad 40→52.)

### P2 · layout · Recent grid is 5 columns (spec 6) and the Recent header has no right affordance
Spec: `Recent` header (`fontSize 18, weight 700, ls -0.3`, `marginTop 26 / marginBottom 14`) with a right affordance (TAG_24 `<Filters />`); grid `gridTemplateColumns: 'repeat(6, 1fr)'; gap: 16` over `SCANS.slice(1)`.
Current: header text correct (ContentView.swift:169) but **no top margin and no right affordance** (no `Spacer()`/`FilterPills`/"See all"); grid uses **5 columns** (the `count: 5` in the grid columns) with gap 16 over `dropFirst()`.
Fix: set the Recent grid to 6 columns; add `Spacer()` + `FilterPills`/a "See all" chip to the Recent header; add the `marginTop ≈ 26` above the header.

### P2 · component · No shared `LibrarySidebar` primitive
The spec is explicit: "Build one reusable sidebar with a `mac` style branch" used by both Pad and Mac. Currently the Mac sidebar is inline in `MacShell` and there is no iPad sidebar at all, so the two device variants cannot share it.
Fix: extract a `LibrarySidebar(go:, width:, mac:)` view (Phone screen file or a shared Studio file) consumed by both the new `PadLibrary` and `MacLibraryPane`.

---

## Notes on reconstructed regions (do not pixel-lock without the live design)
`Featured` body (TAG_0), the Phone dock (TAG_7), the sidebar footer (TAG_11), Mac toolbar accessory (TAG_20) and Open icon (TAG_22), and the Recent-header affordances (TAG_17/24) were proxy-compressed in the source. The current `FeaturedCard` (LibraryScreen.swift:117-141) and the Mac hero `StCard` are reasonable reconstructions of `Featured`/`Featured big`; findings above target only the spans the spec states verbatim (search box, Segmented, "Open", sidebar nav/collections, grid column counts, ordering).
