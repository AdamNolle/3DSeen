# Settings screen — adversarial fidelity review

Ground truth: `docs/design-ref/screens/settings.jsx` (Phone + Pad variants).
Spec: `docs/design-spec/settings.md` ("Source: studio/screens/settings.jsx (fully verbatim)").
Implementation: `Sources/iOS/Studio/Studio/Screens/SettingsScreen.swift`.

Verdict: **significant-gaps**. The shared `Section`/`SettingsCard` atom, profile/account cards, Compute & handoff / Storage / Privacy sections, the Connected device lists, and the overall iPad master/detail structure are faithful. But the very first thing a user sees diverges: an **"Appearance" section that does not exist in the design** is injected at index 0, and the **"Capture defaults" section is restructured** (a design row dropped, a non-design row added, two disclosure values replaced by live store values). Navigation, indices, and IDs are sound — no crash/P0.

Note: most divergences are clearly *deliberate* — the screen was wired to a real `SettingsStore` (see header comment in the Swift file). They are reported anyway because the mandate is fidelity to the authoritative design, and the spec says "fully verbatim". Treat them as product-decision-vs-design reconciliation items, not accidental bugs.

---

## iPhone

### P1 — missing-region — Invented "Appearance" section (not in ground truth)
- Ground truth: `SETTINGS` has exactly 4 sections; the **first** is `'Capture defaults'`. There is no Appearance/Theme/Measurement-units section anywhere in `settings.jsx`.
- Code: `SECTION_META` (SettingsScreen.swift:21-27) prepends `("Appearance", "light", 2)` and `sectionRows(index:)` case 0 renders a `ThemeRow` (System/Light/Dark segmented) + a "Measurement units" menu. On iPhone this is an extra card stacked at the very top, before "Capture defaults".
- Fix: if design fidelity is required, drop section index 0 from the iPhone list (or gate it behind a clearly out-of-band block). If the wiring must stay, update the design ref/spec so this section is part of the ground truth.

### P1 — missing-region — "Audio shutter cue" toggle row dropped from Capture defaults
- Ground truth: `{ l: 'Audio shutter cue', i: 'bolt', toggle: true }` (settings.jsx:7) — toggle, default ON, third row of "Capture defaults".
- Code: `sectionRows` case 1 (SettingsScreen.swift:118-128) renders Default mode, Default detail tier, "Haptic coaching", and "Auto-save to Library". There is no "Audio shutter cue" row anywhere.
- Fix: restore an "Audio shutter cue" (icon `bolt`, default-ON toggle) row in the Capture-defaults section.

### P1 — copy — Non-design "Auto-save to Library" row added to Capture defaults
- Ground truth: Capture-defaults rows are Default mode, Default detail tier, Audio shutter cue, Haptic coaching. No "Auto-save to Library".
- Code: `WiredToggleRow(icon: "download", label: "Auto-save to Library", ...)` (SettingsScreen.swift:127-128).
- Fix: remove the row (or move the new wired preference elsewhere); it is not part of the screen's design.

### P1 — copy — Capture-defaults disclosure values diverge from design defaults
- Ground truth: `'Default mode' → 'Auto-Pilot'` (settings.jsx:5) and `'Default detail tier' → 'Medium'` (settings.jsx:6).
- Code:
  - Default mode menu options are `Object / Space / Landscape` (SettingsScreen.swift:29-31) bound to `settings.defaultMode` whose store default is `.object` (SettingsStore.swift:43). The displayed value is **"Object"**; **"Auto-Pilot" is not even an option**, so it can never appear.
  - Default detail tier options include "Medium" but the store default is `.full` (SettingsStore.swift:47), so the row displays **"Full"**, not the design's "Medium".
- Fix: to match the design out of the box, seed `defaultMode`/`qualityTier` so the displayed labels are "Auto-Pilot"/"Medium", or align the option set + default with the design copy. (Currently a fresh install shows two wrong values vs the reference.)

### P2 — token — Small chips render larger than design
- Ground truth: `PRO` chip `fontSize 10 / weight 700` (settings.jsx:83); `Active` chip `fontSize 10` (settings.jsx:98).
- Code: `StTextChip` → `StChip` is hardcoded to `.font(.sf(12, .semibold))` (Primitives.swift:286); the per-instance size override the JSX applies is lost, so PRO/Active render ~2pt larger and slightly heavier-vs-lighter than spec.
- Fix: allow `StChip`/`StTextChip` to accept a font-size/weight override and pass 10/700 for these instances (also affects the iPad "PRO · ARCHIVAL" 9pt chip).

### Faithful on iPhone
Nav row (back → `model.go(.library)` is a valid route; neutral "Settings" chip; info button no-op with a11y label "Info"), profile card (name 18/-0.4, mono "3DSeen STUDIO · v2.4.1", PRO chip), Compute/Storage/Privacy sections (including the "Smart offload" toggle-wins-over-value rule, SettingsScreen.swift:500), and the Connected card (goodSoft tile + "Active" chip, Rule between devices, unique ForEach ids) all match. The prototype's `<StatusBar/>` mock is correctly omitted (the OS status bar + safe area replace it).

---

## iPad

### P1 — missing-region — "Appearance" section pollutes nav and is the default-selected detail
- Ground truth: `PadSettings` nav lists the 4 `SETTINGS` sections; `active` starts at 0 = **"Capture defaults"**; the big title and eyebrow read "Capture defaults"; the glance grid shows the **3** other sections (`SETTINGS.filter((_, i) => i !== active)`, settings.jsx:167).
- Code: the sidebar nav iterates all 5 `SECTION_META` rows (SettingsScreen.swift:248), so it shows an extra "Appearance" item with count badge "2". `@State active = 0` (SettingsScreen.swift:68) selects "Appearance", so on first open the detail pane's eyebrow/title read **"Appearance"** — a section that does not exist in the design — and the glance grid shows **4** others instead of 3.
- Fix: same as iPhone — remove the Appearance section, and initialize `active` to the first real section ("Capture defaults"). If kept, reconcile the design ref.

### P1 — (inherits) — Capture-defaults divergences apply to the detail pane too
- The dropped "Audio shutter cue" row, the added "Auto-save to Library" row, and the "Auto-Pilot"/"Medium" value mismatches all surface in the iPad detail pane and glance grid because both variants share `sectionRows(_:)`. Same fixes as the iPhone P1s above.

### P2 — token — Same chip-size issue
- The iPad account card's "PRO · ARCHIVAL" chip is `fontSize 9` in the design (settings.jsx:124) but renders at the hardcoded 12pt. Same fix as the iPhone chip finding.

### P2 — layout — Account-card header alignment
- Ground truth: the avatar+text row uses `alignItems: 'center'` (settings.jsx:119).
- Code: `HStack(alignment: .top, ...)` (SettingsScreen.swift:237). Minor vertical offset of the avatar vs the name/email/chip block.
- Fix: use `.center` alignment (or leave — the block heights are close).

### P2 — logic-bug — `FaithfulRow` local toggle state resets on re-appear / section switch
- Code: `FaithfulRow` seeds its `@State on` via `.onAppear { on = row.toggle ?? false }` (SettingsScreen.swift:497-506). The iPad glance grid is a `LazyVGrid` (SettingsScreen.swift:335) and sections move between the large detail card and the glance grid when `active` changes, so the view identity is recreated and/or `onAppear` re-fires. A user who flips one of these (unwired, mock) toggles will see it snap back to its default after scrolling it out/in or switching tabs.
- Impact: low — these Compute/Storage/Privacy toggles are intentionally non-functional design mocks. Still a visible "my toggle reverted" glitch.
- Fix: initialize the state in an `init(row:)` from `row.toggle` instead of `onAppear`, or hoist the toggle state out of the per-row view so it survives re-realization.

### Faithful on iPad
Sidebar account card (avatar 56, name 16/-0.3, mono email, "PRO · ARCHIVAL" chip with top inset, Rule 14, per-section nav with count badges + `fieldFillHi` active fill + accent icon/ink, the 3 static "Account / Plan & billing / About" chevron rows), the Connected card (28×28 tiles, 8×8 good dot), and the detail header (accent eyebrow `3DSeen · {section}`, 38/-1.4 title, the exact subtitle "Settings that apply to every new scan unless overridden in the briefing.", section card, 2-up glance grid of the others) all match the design. `active` is always in range (0…4) and `SECTION_META[active]` / the switch's `default` branch are safe — no crash.
