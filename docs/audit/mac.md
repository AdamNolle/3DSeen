# macOS App Audit — 3DSeen Studio (desktop)

Scope: `Sources/macOS/ContentView.swift`, `3DSeenApp.swift`, `ComputeCoordinator.swift` vs the **Mac**
variants of `docs/design-spec/{library,viewer,compute,export,settings}.md` and the `Mac*` exports in
`docs/design-ref/screens/*.jsx`. READ ONLY — no Swift modified.

The design ships **five** Mac panes: `MacLibrary`, `MacViewer`, `MacCompute`, `MacExport`, `MacSettings`.
Each is a desktop window with a full-height left sidebar + detail; viewer/compute/export add a third
(inspector/telemetry) column. The current app realizes **four** panes (no Settings) behind one global
app-nav sidebar.

---

## Shell / sidebar

- `enum MacSection { library, viewer, compute, export }` (ContentView.swift:21) — **no `settings` case**.
  `3DSeenApp.swift` is a single `WindowGroup` with `.hiddenTitleBar`, **no `Settings { }` scene and no
  `.commands`**. The only "settings" token in the whole macOS target is the SF Symbol *name* on the
  appearance-toggle button (ContentView.swift:111). The entire `MacSettings` preferences window
  (account sidebar + 4 section nav with solid-accent selection + Connected devices; detail toolbar with
  back + "Search settings"; preference `Section` cards of value/toggle rows; "Also in capture defaults"
  block on tab 0) is **absent**. → **P0 missing-mac.**
- The app uses **one persistent global sidebar** (`MacShell.sidebar`, ContentView.swift:64) — 3DSeen logo,
  Library/Model/Compute/Export nav, a Storage card, and a dark/light toggle — reused across every pane.
  The design instead gives **each screen its own sidebar**: Library = `LibrarySidebar mac` (All Scans /
  Objects / Spaces / Landscapes nav + a **Collections** group + storage footer); Settings = account +
  section nav + devices. Consequently the Library pane never surfaces the category nav or Collections.
  Sidebar width 248 (Library spec wants 264; Settings spec wants 248). → **P1 layout.**

## Library pane (`MacLibraryPane`, ContentView.swift:126)

- Toolbar = `"All Scans"` + `"42 items"` chip + **"New Scan"** accent button. Spec toolbar (library.md
  §MAC) wants: title, count chip, a **260-wide search box**, a grid/list **`Segmented [◧, ☰]`**, and an
  **"Open"** button → viewer. Missing the search field and the Segmented toggle entirely; the primary
  button is the wrong action. → **P1 component/layout.** (`StSegmented` already exists but is unused app-wide.)
- "New Scan" button action is `{}` — a **dead no-op** (there is no Mac mode/capture screen). → **P1 wiring.**
- Recent grid is **5 columns** (`count: 5`, line 170); spec is `repeat(6,1fr)`. → **P2 token.**
- Recent thumbs render `ScanThumb(scan: s)` with **no Button/onTapGesture**; spec wraps each in
  `onClick={() => go('viewer')}`. Clicking a recent scan does nothing. → **P2 wiring.**
- Hero band is a bespoke `StCard` (Coverage/Sharpness/PSNR/Watertight + Open/Export/Compute buttons,
  which **are** wired to `section`). Reasonable inference of the unrecoverable `Featured` (TAG_23). → P2.

## Viewer pane (`MacViewerPane`, ContentView.swift:339)

- **No left tool rail.** Spec (viewer.md §Mac) has a 64-wide rail of **7 tools**
  (orbit/measure/pin/layers/light/ar/slice), 42×42 accent-selected buttons on `card2`. The current viewer
  is just `Stage + inspector` — there is no orbit/measure/pin/slice tooling at all. → **P1 missing component.**
- Toolbar = green dot + name + mono meta + "AR Quick Look ready" chip. Spec wants a view-mode
  **`Segmented [Inspect, AR, Compare, Slice]`**, an **AirDrop** ghost button, and an **"Export…"** accent
  button → export. All three missing — so there is **no path from the viewer to Export** except the global
  sidebar. → **P1 component.**
- No bottom-center floating env `Segmented [Studio, Sunset, Soft, Field]` and no top-left
  "Orbit · ⌘-drag to pan" status chip. → **P2 component.**
- Inspector geometry stats are Triangles/Vertices/**UV islands/Watertight**; spec is
  Triangles/Vertices/**Textures (4K PBR)/File size (184 MB)**. Measurements block has **no "Add pin" / "CSV"**
  buttons (spec does). Material override is inline swatches, not the spec `MaterialPicker` (30×30 +
  fieldFillHi/accentLine selection). → **P2 copy/component.**

## Compute pane (`MacComputePane`, ContentView.swift:189) — most faithful (live-wired)

Bound to a real `ComputeCoordinator` (`@StateObject compute`): Multipeer receive → unzip → RealityKit
`PhotogrammetrySession` → USDZ, with a real stage stepper + Meter + transfer log + `simulate()`. Gaps:

- Pipeline rail lacks the spec's **"Live throughput" card** (Frames/s 184 · Elapsed 2:38 · Remaining 1:52)
  and the **per-stage subtitles** ("334 frames · aligned", "MVS · depth fusion", …). → **P1 component.**
- Telemetry panel is Hardware (3 meters) + Transfer log only. Spec adds a 4th **"Unified memory"** meter,
  an entire **Thermals** row (SoC 58°C / Fans 2400rpm / Power 46W), and a bottom **"Open when ready"**
  accent button → viewer (so a finished render never offers to open the model). → **P1 missing component.**
- Width drift: rail 300 vs 320, telemetry 280 vs 300. Copy "RealityKit on Apple Silicon" vs "on M4 Max"
  (more honest), live-glass "Frames" vs "Depth maps" (wired to real `receivedFrames`), and a synthetic
  7th "Complete" stage vs spec's 6. → **P2 token/copy.**

## Export pane (`MacExportPane`, ContentView.swift:417) — partially live

`export()` performs a **real** `ModelExporter().export(...)` into Downloads + `NSWorkspace` Finder reveal. Gaps:

- Config panel is Format list + status + CTA. Spec config also has an **"Options"** group (4 `Toggle` rows:
  Include measurements / Bake materials to 2K / Scale to scene / Color-managed) and a **"Destination"**
  `DestRow` (AirDrop / Adam's MBP / iCloud / Files). Both **entirely absent**. → **P1 missing component.**
- No **config → progress → done** flow: spec drives an `StRing` `ProgressView` then a `DoneView`
  (success badge + "Export again" / "Done"). Current does a synchronous export + one-line status string —
  functionally real, but the spec's visual flow / `StRing` is absent. → **P1 interaction.**
- Preview shows only the top-left chip; spec adds a bottom-center **stats glass** (Format/Size/Triangles/
  Textures). FormatRow has **no 20×20 radio check-well** (and no "BEST" chip). CTA copy is
  `"Export usdz"` (`engineFormat.rawValue`) vs spec `"Export USDZ · 184 MB"`; the
  `~/Exports/3DSeen/celestial-bust{ext}` path line is absent. → **P2 component/copy.**

---

## Verdict

Compute is the only pane wired end-to-end and close to spec; Export is functionally real but missing
half its config UI and its whole progress/done flow; Library and Viewer are static mocks missing their
search/segmented/tool-rail chrome; and **Settings does not exist at all**. The app also collapses the
design's five per-screen sidebars into one global app-nav sidebar, dropping Library's Collections/category
nav and the Settings account panel. Biggest gaps, in order: (1) no Settings pane, (2) viewer tool rail +
export options/destination + compute throughput/thermals/open-when-ready, (3) library search/segmented and
dead/untappable affordances.
</content>
</invoke>
