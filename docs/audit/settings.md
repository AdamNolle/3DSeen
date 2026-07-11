# Settings / Profile — fidelity audit

Spec: `docs/design-spec/settings.md` · Source of truth: `docs/design-ref/screens/settings.jsx` (exports `PhoneSettings`, `PadSettings`, `MacSettings`).
Current Swift: `Sources/iOS/Studio/Screens/SettingsScreen.swift` (iPhone port only).
Shared: `Sources/Shared/DesignSystem/{Theme,Primitives}.swift`, `Sources/iOS/Studio/StudioChrome.swift`, `Sources/iOS/Studio/StudioRouter.swift`, `Sources/macOS/ContentView.swift`.

## Verdict

The iPhone variant (`PhoneSettings`) is ported with high fidelity — data model, sections, rows, toggle ownership, connected list, and back navigation all match. The two big gaps are structural: **the iPad bespoke master/detail layout (`PadSettings`) is entirely absent** (iPad renders the iPhone single-scroll list merely width-capped via `readableContentWidth()`), and **the Mac preferences window (`MacSettings`) does not exist** (the macOS `MacSection` enum has no `settings` case and there is no `Settings` scene). Remaining items are P2 polish: shared `StChip` cannot render the spec's 9–10px chip sizes, a couple of small spacing/icon-size deltas, and the Avatar's inner specular highlight is missing.

---

## iPhone — `PhoneSettings` vs `SettingsScreen`

Overall faithful. Minor polish items only.

### P2 · component · Chips render at 12px, spec wants 9–10px
Spec phone PRO chip: accent `Chip` **"PRO"** at `fontSize 10 / weight 700` (jsx L83); device "Active" chip at `fontSize 10` (jsx L98). `StChip`/`StTextChip` hardcode `.font(.sf(12, .semibold))` (`Primitives.swift` L252, L268-272) with no size override, so both chips render too large.
Fix: add an optional `fontSize`/`weight` parameter to `StChip`/`StTextChip` (default 12/.semibold), then pass `10`/`.bold` for PRO and `10` for Active. Shared fix — also unblocks iPad ("PRO · ARCHIVAL" @9) and Mac.

### P2 · layout · Section/Connected cards drop the 4px vertical card padding
Spec: `Section` and the Connected list are `Card radius=20, padding '4px 16px'` (settings.md §"Section"; jsx L58, L92). Swift renders `StCard(radius: 20, pad: 0)` and only applies `.padding(.horizontal, 16)` (`SettingsScreen.swift` L87, L105, L134-141) — the 4px top/bottom is missing, so the first/last row sits 4px tighter against the card edge.
Fix: wrap the inner `VStack` with `.padding(.vertical, 4).padding(.horizontal, 16)` in `SectionCard` and the Connected card.

### P2 · layout · Missing 8px top inset on scroll body
Spec scroll body padding is `'8px 20px 40px'` (jsx L71). Swift applies `.padding(.horizontal, 20)` + `.padding(.bottom, 40)` (L108-109) but no `.padding(.top, 8)`, so the nav row is flush to the top of the scroll area.
Fix: add `.padding(.top, 8)` to the content `VStack`.

### P2 · token · Info button icon is 17px, spec is 16px
Spec right info button: `Ic info s=16 c=T.text2` (settings.md §iPhone L62; jsx L75). `CircleIconButton` hardcodes `StIcon(name: icon, size: 17, ...)` (`StudioChrome.swift` L15), so the info glyph is 17px (back is correctly 17). Cosmetic.
Fix: allow `CircleIconButton` to accept an icon size, or render the info button inline with `StIcon(name: "info", size: 16, color: theme.text2)` in a 36×36 `Circle().fill(theme.fieldFill)`.

### P2 · component · Avatar missing inner specular highlight
Spec Avatar shadows: `inset 0 1px 1px rgba(255,255,255,0.4), 0 2px 8px T.accentSoft` (settings.md §Avatar; jsx L35). Swift `Avatar` applies only the outer `.shadow(color: theme.accentSoft, radius: 8, y: 2)` (`SettingsScreen.swift` L126); the inset top-light is absent.
Fix: add an overlay `Circle().stroke(.white.opacity(0.4), lineWidth: 1).blur(0.5).mask(top-half)` or an inner top highlight gradient to approximate the inset rim. (Gradient endpoint `#1B3A8C` is correctly a literal per spec L140 — not a finding.)

### P2 · token · Display weight 720 mapped to `.heavy` (800)
Spec name "Adam Nolle" is `18px / weight 720` (jsx L80). Swift uses `.font(.sf(18, .heavy))` (`SettingsScreen.swift` L72); `.heavy` is 800, heavier than 720 (`.bold` = 700 is closer). This is an app-wide mapping convention (foundation §2 lists 650–720 as "heavy display"), so fix systemically if at all, not just here.

### Confirmed correct (no action)
- Back → `model.go(.library)`; info button intentionally no-op (matches spec L69).
- "Smart offload" row has both `v` and `toggle:true` → renders the **toggle** (jsx L49 `row.toggle !== undefined` wins). Swift `if row.toggle != nil` (L159) reproduces this exactly.
- Privacy `toggle:false` rows render an OFF toggle (not a value/chevron) — `row.toggle != nil` true. Correct.
- Per-row local toggle state with no persistence is intentional (spec §Implementation notes: "static design mock", `onToggle` never wired). `@State private var on` + `.onAppear { on = row.toggle ?? false }` matches. **Not a wiring finding.**
- Connected device tile correctly has **no** `inset 0.5px line` border (only the `SettingRow` icon tile does) — matches jsx L96 vs L45.

---

## iPad — `PadSettings` — MISSING (P1)

### P1 · missing-ipad · Bespoke sidebar + detail layout absent; iPad shows the iPhone list
`StudioRouter` routes `.settings` to a single `SettingsScreen()` for all size classes (`StudioRouter.swift` L73); the screen has no `horizontalSizeClass` branch and only calls `.readableContentWidth()` (L110), so on iPad it is the iPhone single-scroll list centered at 720px. The spec requires a two-region master/detail (settings.md §iPad; jsx L110-178):

- **Content** absolute inset 0, `top 30` under `PadStatusBar`, row, `gap 18`, `padding 24`.
- **Sidebar** `width 272`, flex column `gap 14`:
  - **Account card** `Card radius=22 padding 16`: `Avatar s=56`; name "Adam Nolle" `16px / 720 / -0.3`; mono **"adam@nolle.studio"** `10px / text3` (note: email here, not "3DSeen STUDIO · v2.4.1"); accent `Chip` **"PRO · ARCHIVAL"** `fontSize 9, marginTop 5`. `Rule` `margin 14px 0`. Section-nav list (one button per section): row `gap 11, padding '9px 10px', radius 11`, background `T.fieldFillHi` when active else transparent; `Ic sec.icon s=16` color `active ? accent : text2`; name `13.5px`, weight `active ? 650 : 500`, color `active ? ink : text2`; right mono **row count** = `sec.rows.length` `10.5px / text3`; tap → `setActive(i)`. Then 3 static rows **"Account"**, **"Plan & billing"**, **"About"** `13.5px / 500 / text2` each with `Ic chev s=13 c=text4` (no action).
  - **Connected card** `Card radius=20 padding 16`: `Label` color `T.good` **"Connected"**; devices `28×28` radius-8 tile (`d.on ? goodSoft : fieldFill`, `Ic laptop s=14`), name `12.5px / 600`, mono sub `10px / text3`, and `8×8` `T.good` dot if active.
- **Main detail** (scroll, flex 1): `Label` color `T.accentText` **"3DSeen · {SETTINGS[active].sec}"**; big title = active section name `38px / 730 / -1.4 / lineHeight 1.02 / marginTop 6`; subtitle **"Settings that apply to every new scan unless overridden in the briefing."** `13.5px / text2 / marginTop 8`; active section as `Section` card (marginTop 18); then a **"glance" grid** `gridTemplateColumns '1fr 1fr', gap 14, marginTop 18` of every *other* section (`SETTINGS.filter((_, i) => i !== active)`), each a small `Label` + `Section`.

Fix: add a `PadSettings` view (e.g. `SettingsScreen` branches on `horizontalSizeClass == .regular`) with `@State private var active = 0`, an `HStack(spacing: 18)` of a 272-wide sidebar `VStack(spacing: 14)` and a `ScrollView` detail column. Reuse the existing `SectionCard` (already the shared atom) for both the active section and the glance grid (`LazyVGrid(columns: 2)`). The section-nav buttons drive `active`; eyebrow/title/(toolbar) all interpolate `SETTINGS[active].title` from one source. Add an `email` field to the account data and a row-count display.

---

## Mac — `MacSettings` — MISSING (P1)

### P1 · missing-mac · No Settings preferences window in the macOS target
The macOS app's sidebar enum is `enum MacSection { case library, viewer, compute, export }` (`ContentView.swift` L21-22) — there is **no `settings` case** — and `3DSeenApp.swift` defines only a `WindowGroup` with no SwiftUI `Settings { }` scene (no ⌘, preferences). Foundation §8 explicitly includes settings in the Mac flow (`library → viewer → compute → export → settings`), and settings.md §Mac fully specifies `MacSettings` (jsx L181-245):

- **Sidebar** `width 248`, `background T.card2`, `borderRight 0.5px line`, `padding '52px 14px 18px'`, full-height (no separate title bar above it).
  - **Account header** row `gap 11, padding '4px 8px 14px'`: `Avatar s=44`; name "Adam Nolle" `14.5px / 700 / -0.3`; mono **"PRO · ARCHIVAL"** `9.5px / text3`.
  - **Section nav**: one button per section, row `gap 11, padding '8px 10px', radius 9`, background **`T.accent`** when active (solid accent fill — distinct from iPad's `fieldFillHi`), else transparent; `Ic sec.icon s=16` color `active ? onAccent : text2`; name `13.5px`, weight `active ? 600 : 500`, color `active ? onAccent : ink`; tap → `setActive(i)`. `Rule margin '8px 8px'`. Then 4 static rows **"Account"**, **"Plan & billing"**, **"Devices"**, **"About"** `13.5px / 500 / text2` (no chevron, no action). Spacer.
  - **Connected** `Card inset radius=14 padding 13`: `Label` color `T.good` "Connected"; each device row `gap 9`: `8×8` dot (`d.on ? good : text4`), name `12.5px / 600 / ink`, right mono **SoC** = `d.s.split(' · ')[1]` ("M4 Max" / "M2") `9.5px / text3`.
- **Detail pane** (flex 1, column):
  - **Toolbar** `height 52, borderBottom 0.5px line, background T.card2, padding '0 22px', gap 12`: back chip-button `height 30, radius 8, fieldFill, Ic back s=15`, label **"Library"** → `go('library')`; active section name `15px / 700 / -0.3`; spacer; search-field mock `height 32, padding '0 12px', radius 9, fieldFill, width 220, inset 0.5px line`, `Ic search s=15 c=text3` + placeholder **"Search settings"** `13px / text3`.
  - **Scroll content** `padding 28`, centered `maxWidth 720`: `Label` color `T.accentText` **"3DSeen Studio · Preferences"**; title = active section name `30px / 730 / -1`; subtitle **"Defaults applied to every new scan and handoff. Override per-project in the capture briefing."** `14px / text2 / lineHeight 1.45`; active `Section` card (marginTop 20); **only when `active === 0`** an extra block (marginTop 22): `Label` **"Also in capture defaults"** + `Section` for `SETTINGS[1]` (Compute & handoff).

Fix: add `case settings` to `MacSection` (title "Settings", icon "settings"), build a `MacSettingsPane` matching the above, and either route it in the existing sidebar/detail split or wire a real `Settings { }` scene (⌘,). Reuse `SectionCard`/`StCard(inset:)`/`StLabel(color:)`. Note the **solid-accent** selected-section styling (`background theme.accent`, `onAccent` text/icon) — do NOT reuse iPad's `fieldFillHi` highlight (spec §Implementation notes call this out explicitly).

---

## Summary of fixes by priority
- **P1**: build `PadSettings` (iPad master/detail) and `MacSettings` (macOS preferences window) — both are entirely missing; iPad currently shows the iPhone list width-capped, Mac has no settings at all.
- **P2 (iPhone polish)**: parameterize `StChip` font size (chips render 12px vs spec 9–10px); add 4px vertical card padding to sections + connected card; add 8px scroll-body top inset; info icon 16px not 17; Avatar inner specular highlight; (systemic) 720-weight → `.heavy` mapping.
