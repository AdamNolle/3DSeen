# Foundation audit — 3DSeen design system (Swift) vs `00-foundation.md` + `ds.jsx`

Read-only audit of `Sources/Shared/DesignSystem/{Theme,LiquidGlass,Primitives}.swift`,
`Sources/Shared/Studio/StudioRender.swift`, and iOS chrome/router/haptics, cross-checked against
`docs/design-spec/00-foundation.md` §1/§3/§5 and the ground-truth `docs/design-ref/ds.jsx`.

Verdict: **color tokens are essentially perfect** (all 30 light + 30 dark hex/alpha values match exactly).
The fidelity gaps are concentrated in (a) **shadow tokens** (none exist; buttons/cards approximate or omit),
(b) the **stage gradient geometry** (linear instead of radial), (c) a handful of **component variants**
(glass button, primary/accent button shadows, Stat weight, Meter animation), (d) **dead primitives/render
helpers** (Segmented, Spark, Histogram, FrameStrip, Meter-on-iOS), and (e) **missing infra wiring**
(iOS dark-mode toggle, iPad split scaffold, settings persistence, duplicate-source build break) that blocks
screen work.

---

## 1. Color tokens — every value verified

Checked all 32 token rows × 2 themes against `ds.jsx` LIGHT/DARK. **Result: 100% match**, including the
ones the brief flagged to watch:

| token | light | dark | status |
|---|---|---|---|
| canvas, bg, **bgInset**, card, **card2** | ✓ | ✓ | exact |
| ink, text2, text3, **text4**, onAccent | ✓ | ✓ | exact |
| line, **lineStrong**, fieldFill, **fieldFillHi** | ✓ | ✓ | exact |
| accent, **accentText**, **accentSoft**, **accentLine** | ✓ | ✓ | exact |
| good/**goodSoft**, warn/**warnSoft**, bad/**badSoft** | ✓ | ✓ | exact |
| glassFill, glassBorder, **glassShine** | ✓ | ✓ | exact |
| primaryFill, primaryText | ✓ | ✓ | exact |
| grid, **axis** | ✓ | ✓ | exact |
| `Stone` hi/mid/lo/deep | n/a | n/a | exact (`#ECE4D6/#BFA98C/#6B5C49/#372E24`) |

**Missing tokens / not represented as tokens:**

- **`stageRim`** — absent from the `Theme` struct. The correct values (`rgba(255,255,255,0.6)` light,
  `rgba(255,255,255,0.10)` dark) ARE reproduced, but **inlined** as `Color.white.opacity(0.6)/0.10` in
  `Stage` (`StudioRender.swift:21`). No visual bug; it should be promoted to a token so other surfaces
  (viewfinder, mac stages) reuse it.
- **`glassShadow` / `cardShadow` / `cardShadowLg` / `primaryShadow`** — none of the four CSS shadow recipes
  exist as tokens. They are partially re-implemented inline (see §2) and partially **omitted entirely**.
- `axis` is defined but has **0 consumers** anywhere (no chart draws an axis line) — harmless but dead.

**Notes for the spec doc (not impl bugs):**
- §3 "Ring" text says the track color is `line`; ground-truth `ds.jsx:299/306` uses `T.fieldFillHi`. The Swift
  `StRing` correctly uses `fieldFillHi`. **Fix the spec markdown**, not the code.

---

## 2. Shadows (CSS box-shadow → SwiftUI)

`ds.jsx` defines two-layer shadows. Swift has **no shadow tokens**; each primitive rolls its own:

| recipe | spec (light big layer) | Swift impl | gap |
|---|---|---|---|
| `glassShadow` | `0 12px 32px rgba(20,20,30,.10)` + `0 1px 2px …06` | `LiquidGlass.swift:75-76` — 2 layers, `black .10 r16 y12` + `black .06 r2 y1` | good approximation; uses pure black not `rgba(20,20,30)`; dark big-layer opacity `.32` vs spec `.5` |
| `cardShadow` | `0 10px 30px rgba(20,20,30,.06)` + `0 1px 2px …04` | `Primitives.swift:61` — **single** layer `black .06 r10 y6` | conflates blur(30) with offset(10); drops the tight 1px contact layer |
| `cardShadowLg` | `0 24px 60px rgba(20,20,30,.10)` + `0 2px 6px …05` | `Primitives.swift:61` (`elevated`) — **single** layer `black .10 r24 y12` | same: blur 60 → radius 24; no tight layer |
| `primaryShadow` | `0 6px 16px rgba(0,0,0,.16)` + `0 1px 2px …18` | **none** — `StButton` primary is a flat `Capsule().fill(primaryFill)` | primary button has no shadow at all |

Recommend: add a `Theme.shadow(_ token)` helper returning ordered `(color,radius,x,y)` layers and a
`.stShadow(_:)` modifier so Card/Glass/Button all read the same two-layer recipes.

---

## 3. Components (§3) vs `Primitives.swift` / `LiquidGlass.swift`

Every archetype exists (`StIcon, StCard, StButton, StLabel, StStat, StSegmented, StToggle, StChip,
StTextChip, StMeter, StRing, StRule`, `StGlass` + `.liquidGlass`). Metric check:

| component | match | deviations |
|---|---|---|
| **Glass** | strong | radius 18 ✓; fill/border/rim/sheen/inner-shade ✓; **dark tone** fill `rgba(26,24,21,.52)`/border`.18`/rim`.55`/sheen`.12` ✓. `.ultraThinMaterial` stands in for `blur24 saturate200 brightness` — saturation/brightness boost not reproduced (acceptable per §9). |
| **Card** | ok | radius 20 ✓, `card`/`bgInset` ✓, 0.5 line ✓; shadow single-layer approx (see §2). |
| **Button** | partial | radius 999/w600/ls−0.2/gap8 ✓; heights 52/44/36 ✓; fonts 16/15/13.5 ✓; pad 14/20 ✓. **`glass` kind is wrong** — `Primitives.swift:98` is a flat `Capsule().fill(glassFill)`: no blur, no inset border, no glassShadow (spec wants blur20 + inset border + glassShadow). **`primary` has no primaryShadow; `accent` has no soft accent shadow.** |
| **Label** | exact | mono 10.5 / w600 / ls1.4 / caps / text3 ✓. |
| **Stat** | minor | key mono 9.5 w600 ls1 text3 ✓; value sizes 40/28/22/17 ✓, ls−0.6 ✓, tabular ✓, unit 0.46× w600 text3 ✓. **Weight uses `.bold` (700) vs spec/`ds.jsx` `680`**; `lineHeight 1.04` not applied (single-line, negligible). |
| **Segmented** | exact | pad3/radius999/fieldFill/inset line/gap2 ✓; item 36/30, pad14, selected `card`+shadow+ink, fonts 13.5/12.5 ✓. **But used by zero screens (dead).** |
| **Toggle** | exact | 50×30, pad2, knob 26×26 white+shadow ✓; on→`good` knob-right, off→`fieldFillHi`+inset line knob-left, 0.2s ✓. |
| **Chip** | exact | pad 4×10, radius999, font12 w600 ls−0.1, gap5 ✓; all 5 tones ✓. |
| **Meter** | minor | height6/radius99/track fieldFillHi/fill accent/width value×100% ✓. **Missing the `.5s` animated width.** Used only on macOS. |
| **Ring** | exact | size72/stroke7, track fieldFillHi (matches `ds.jsx`), arc accent rot−90 round-cap ✓; label size×0.3 w700 ink + sub mono8.5 w600 text3 ✓. |
| **Rule** | exact | 0.5 line; vertical width.5 ✓. |
| **Icon** | ok | all 49 prototype names mapped to SF Symbols (`Primitives.swift:14-31`); stroke→filled approximations. |

---

## 4. Render helpers (§5) — `StudioRender.swift`

| helper | exists | fidelity | 3D need |
|---|---|---|---|
| `Stage` | ✓ | radius16, `theme.stage` fill, stageRim overlay inline ✓ | — |
| `HeroModel` | ✓ | **2D `Canvas` bust** with pbr/wire/metal/matte branches — decorative only | **needs real 3D in Viewer** (SceneKit/RealityKit/MetalSplatter). Real splat renderer exists (`SplatViewerScreen`/`GaussianSplat.swift`) but is reached only via the Viewer `splat` tool, not the default hero. |
| `CoverageSphere` | ✓ | 22 wedges ✓, latitude rings ✓, covered/partial sets hardcoded | 2D Canvas OK (live HUD) |
| `CoverageDome` | ✓ | 3 shells (78/63/48) × 30 wedges ✓, numbered drop pins from `[Dropout]` ✓ | 2D Canvas OK |
| `ScanThumb` | ✓ | aspect 1/1.16 ✓, radius14 ✓, glass mode chip TL ✓, name+`mode·tier·mb MB` BL ✓; **`ScanTone.pair` hexes match all 6 tones exactly** | 2D OK |
| `Spark` | ✓ | fill .10 ✓, 1.6 stroke ✓, end dot ✓ | Canvas OK — **but wired to no screen** |
| `Histogram` | ✓ | 3 RGB curves (`#D06A66/#5BA86E/#5B85C8`) ✓ | Canvas OK — **unused** |
| `FrameStrip` | ✓ | thumb row w/ rejected `×` ✓ | **belongs on Review screen (§5) — unused** |

---

## 5. Dead / unused (recommend wire-up or removal)

- **`StSegmented`** — defined, **0 screen consumers**. Per design it should drive: Quality tier toggle,
  Viewer/Mac material picker, and Settings option groups. Wire it in or delete.
- **`Spark` / `Histogram` / `FrameStrip`** — defined, **0 consumers**. `FrameStrip` → ReviewScreen;
  `Histogram`/`Spark` → quality/compute telemetry per the prototype. Wire or remove.
- **`StMeter`** — used only by macOS; iOS Briefing/Compute progress should use it instead of bespoke bars.
- **`Theme.sf` / `Theme.mono`** (`Theme.swift:84-85`) — String constants `"SF Pro Display"`/`"SF Mono"`,
  **0 consumers**; the real helpers `Font.sf/.mono` use `.system(...)`. Either delete the strings or make the
  helpers honor the Display/Text optical split.
- **`View.adaptiveColumnCount(_:_:)`** (`StudioChrome.swift:89`) — **always returns `compact`**; dead/buggy
  stub shadowed by the working `AdaptiveColumns.count`. Remove.
- **`theme.axis`** — token with no consumer.
- **Duplicate sources** — untracked `Sources/iOS/Studio/{StudioRender,SampleData}.swift` duplicate the
  `Sources/Shared/Studio/` versions; `project.yml` globs both folders into the iOS target → redeclaration
  build break after `xcodegen generate`. Delete the iOS copies or exclude a folder per target.

---

## 6. Wiring infra gaps (P1 — these block screen work)

- **Dark mode unreachable on iOS.** `StudioModel.dark` is honored at the root
  (`StudioRouter.swift:48,59`) but **no iOS control toggles it** and it is **not bound to system
  `@Environment(\.colorScheme)`** (spec §line 7 wants St "resolved from color scheme"). Add a Settings
  appearance control and/or follow the system scheme. macOS already has its sidebar toggle.
- **No iPad bespoke layout.** No `NavigationSplitView`/sidebar/master-detail; iPad = width-capped iPhone
  screens (`readableContentWidth`) + Library 2→4 grid. Spec §8 mandates a bespoke split/sidebar. Need a
  size-class-driven scaffold (`NavigationSplitView` for regular width) before regular-width screen specs land.
- **No settings persistence store.** Settings toggles are per-row `@State`, reset on remount; nothing reads
  `@AppStorage`/UserDefaults/SwiftData. Add a persisted settings model (also where the dark toggle should live).

---

## 7. a11y / perf

- **`StToggle`** is a generic `Button` with a `Circle` — no `.accessibilityAddTraits(.isToggle)` / on-off
  value, so VoiceOver announces "button" without state. Add toggle trait + value.
- **`StIcon`** standalone images carry no accessibility label/`.accessibilityHidden(true)` when decorative;
  fine inside labeled buttons (`CircleIconButton` does set labels) but risky when used as bare status glyphs.
- **Perf OK.** Canvas renders (HeroModel/Coverage*/ScanThumb/Spark/Histogram) are cheap and re-evaluate only
  on theme/size change; `Color(hex:)` Scanner cost is init-time only. `.monospacedDigit()` used correctly for
  tabular numerals. No runaway/infinite animations in the foundation layer (pulse/sheen live per-screen).
