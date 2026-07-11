/* ============================================================================
   EXTRACTION NOTE — READ FIRST
   This file (studio/screens/library.jsx) was delivered through a compressing
   proxy that deduplicates internal redundancy. 26 inner JSX spans could NOT be
   retrieved verbatim and are preserved below as `{{HEADROOM_TAG_N}}` markers so
   this artifact stays honest about what was actually received.
   The structural skeleton (all comments, all style objects, all literal copy &
   numbers OUTSIDE the markers) IS verbatim.
   A best-inference reconstruction of every marker — with confidence levels — is
   in the RECONSTRUCTION APPENDIX at the bottom of this file, and in
   docs/design-spec/library.md. mode.jsx and briefing.jsx in this folder are
   fully verbatim (came through uncompressed).
   ============================================================================ */

// studio/screens/library.jsx — Home / scan library (iPhone · iPad · Mac)

function Featured({ scan, go, big = false }) {
  return (
    {{HEADROOM_TAG_0}}
  );
}

function Filters({ active = 'All', onPick }) {
  const counts = { All: 42, Object: 28, Space: 9, Landscape: 5 };
  return (
    <div style={{ display: 'flex', gap: 8 }}>
      {Object.keys(counts).map(k => {
        const on = k === active;
        return (
          <button key={k} className="st-tap" onClick={() => onPick && onPick(k)} style={{
            padding: '7px 13px', borderRadius: 999, border: 'none', cursor: 'pointer',
            background: on ? T.ink : T.fieldFill, color: on ? T.bg : T.text2,
            boxShadow: on ? 'none' : `inset 0 0 0 0.5px ${T.line}`,
            fontFamily: T.sf, fontSize: 13, fontWeight: 600, letterSpacing: -0.1, display: 'flex', gap: 6, alignItems: 'center',
          }}>
            {k}<span className="st-num" style={{ fontSize: 11, opacity: 0.6 }}>{counts[k]}</span>
          </button>
        );
      })}
    </div>
  );
}

// ─── iPhone ───────────────────────────────────────────────────────────────────
function PhoneLibrary({ go }) {
  const [filter, setFilter] = React.useState('All');
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      {{HEADROOM_TAG_1}}
      <div className="st-scroll" style={{ position: 'absolute', inset: 0, top: 54, bottom: 0, overflow: 'auto' }}>
        <div style={{ padding: '8px 20px 120px' }}>
          {/* header */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingTop: 4 }}>
            <Label>3DSeen · 42 scans</Label>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="st-tap" onClick={() => go('settings')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', background: T.fieldFill, display: 'grid', placeItems: 'center', cursor: 'pointer' }}>{{HEADROOM_TAG_2}}</button>
            </div>
          </div>
          <div style={{ fontSize: 36, fontWeight: 720, letterSpacing: -1.2, color: T.ink, marginTop: 6, lineHeight: 1 }}>Library</div>
          <div style={{ fontSize: 13.5, color: T.text2, marginTop: 6 }}>11.4 GB on device · 2 syncing to iCloud</div>

          {/* search */}
          <div style={{ marginTop: 16, display: 'flex', alignItems: 'center', gap: 10, height: 44, padding: '0 14px', borderRadius: 14, background: T.fieldFill, boxShadow: `inset 0 0 0 0.5px ${T.line}` }}>
            {{HEADROOM_TAG_3}}
            <span style={{ fontSize: 14.5, color: T.text3 }}>Search scans, tags, materials</span>
          </div>

          {/* featured */}
          <div style={{ marginTop: 16 }}>
            {{HEADROOM_TAG_4}}
          </div>

          {/* filters */}
          <div style={{ marginTop: 18, marginBottom: 12 }}>
            {{HEADROOM_TAG_5}}
          </div>

          {/* grid */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            {SCANS.slice(1, 7).map(s => (
              <div key={s.id} onClick={() => go('viewer')}>{{HEADROOM_TAG_6}}</div>
            ))}
          </div>
        </div>
      </div>

      {/* floating new-scan dock */}
      <div style={{ position: 'absolute', bottom: 28, left: 0, right: 0, display: 'flex', justifyContent: 'center', zIndex: 20 }}>
        {{HEADROOM_TAG_7}}
      </div>
    </div>
  );
}

// ─── shared sidebar (iPad / Mac) ───────────────────────────────────────────────
function LibrarySidebar({ go, w = 248, mac = false }) {
  const nav = [
    { i: 'grid', t: 'All Scans', c: 42, on: true },
    { i: 'cube', t: 'Objects', c: 28 },
    { i: 'room', t: 'Spaces', c: 9 },
    { i: 'landscape', t: 'Landscapes', c: 5 },
  ];
  const collections = [['Museum Loan', 12, '#9B8769'], ['Renovation 5B', 8, '#C58F4B'], ['Field · Granite', 5, '#4C5A60'], ['Cassette Series', 9, '#566C70']];
  return (
    <div style={{ width: w, flexShrink: 0, display: 'flex', flexDirection: 'column', gap: 6, height: '100%' }}>
      {!mac && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '4px 8px 12px' }}>
          <div style={{ width: 30, height: 30, borderRadius: 9, background: T.accent, display: 'grid', placeItems: 'center' }}>{{HEADROOM_TAG_8}}</div>
          <div>
            <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>3DSeen</div>
            <div className="st-num" style={{ fontFamily: T.mono, fontSize: 9.5, color: T.text3 }}>v2.4 · STUDIO</div>
          </div>
        </div>
      )}
      {nav.map(r => (
        <button key={r.t} className="st-tap" style={{
          display: 'flex', alignItems: 'center', gap: 11, padding: '9px 12px', borderRadius: 12, border: 'none', cursor: 'pointer',
          background: r.on ? T.fieldFillHi : 'transparent', textAlign: 'left',
        }}>
          {{HEADROOM_TAG_9}}
          <span style={{ flex: 1, fontSize: 14, fontWeight: r.on ? 650 : 500, color: r.on ? T.ink : T.text2 }}>{r.t}</span>
          <span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3 }}>{r.c}</span>
        </button>
      ))}
      {{HEADROOM_TAG_10}}
      <Label style={{ padding: '0 12px 4px' }}>Collections</Label>
      {collections.map(([t, c, dot]) => (
        <button key={t} className="st-tap" style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '7px 12px', borderRadius: 12, border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left' }}>
          <span style={{ width: 9, height: 9, borderRadius: 3, background: dot }} />
          <span style={{ flex: 1, fontSize: 13.5, fontWeight: 500, color: T.text2 }}>{t}</span>
          <span className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text4 }}>{c}</span>
        </button>
      ))}
      <div style={{ flex: 1 }} />
      {{HEADROOM_TAG_11}}
    </div>
  );
}

// ─── iPad ───────────────────────────────────────────────────────────────────────
function PadLibrary({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      {{HEADROOM_TAG_12}}
      <div style={{ position: 'absolute', inset: 0, top: 30, display: 'flex', padding: 22, gap: 22 }}>
        {{HEADROOM_TAG_13}}
        <div className="st-scroll" style={{ flex: 1, overflow: 'auto', minWidth: 0 }}>
          {/* search row */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 10, height: 46, padding: '0 14px', borderRadius: 14, background: T.fieldFill, boxShadow: `inset 0 0 0 0.5px ${T.line}` }}>
              {{HEADROOM_TAG_14}}
              <span style={{ fontSize: 14.5, color: T.text3 }}>Search scans, tags, materials…</span>
            </div>
            <Button kind="accent" onClick={() => go('mode')}>{{HEADROOM_TAG_15}} New Scan</Button>
          </div>

          {/* featured */}
          <div style={{ marginTop: 18 }}>{{HEADROOM_TAG_16}}</div>

          {/* recent */}
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 24, marginBottom: 12 }}>
            <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: -0.4, color: T.ink }}>Recent</div>
            {{HEADROOM_TAG_17}}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 14 }}>
            {SCANS.slice(1).map(s => (
              <div key={s.id} onClick={() => go('viewer')}>{{HEADROOM_TAG_18}}</div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Mac (Studio) ───────────────────────────────────────────────────────────────
function MacLibrary({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, display: 'flex' }}>
      {/* left sidebar */}
      <div style={{ width: 264, flexShrink: 0, background: T.card2, borderRight: `0.5px solid ${T.line}`, padding: '52px 16px 18px', display: 'flex', flexDirection: 'column' }}>
        {{HEADROOM_TAG_19}}
      </div>
      {/* main */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {/* toolbar */}
        <div style={{ height: 52, flexShrink: 0, borderBottom: `0.5px solid ${T.line}`, display: 'flex', alignItems: 'center', gap: 14, padding: '0 20px', background: T.card2 }}>
          <div style={{ width: 56 }} />
          <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>All Scans</div>
          {{HEADROOM_TAG_20}}
          <div style={{ flex: 1 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 32, padding: '0 12px', borderRadius: 9, background: T.fieldFill, width: 260, boxShadow: `inset 0 0 0 0.5px ${T.line}` }}>
            {{HEADROOM_TAG_21}}<span style={{ fontSize: 13, color: T.text3 }}>Search</span>
          </div>
          <Segmented size="sm" options={[{ value: 'grid', label: '◧' }, { value: 'list', label: '☰' }]} value="grid" onChange={() => {}} />
          <Button kind="accent" size="sm" onClick={() => go('viewer')}>{{HEADROOM_TAG_22}} Open</Button>
        </div>
        {/* content */}
        <div className="st-scroll" style={{ flex: 1, overflow: 'auto', padding: 24 }}>
          {/* hero band */}
          {{HEADROOM_TAG_23}}

          {/* recent grid */}
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 26, marginBottom: 14 }}>
            <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Recent</div>
            {{HEADROOM_TAG_24}}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: 16 }}>
            {SCANS.slice(1).map(s => (
              <div key={s.id} onClick={() => go('viewer')}>{{HEADROOM_TAG_25}}</div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneLibrary, PadLibrary, MacLibrary, LibrarySidebar, Filters });

/* ============================================================================
   RECONSTRUCTION APPENDIX — best-inference content for each {{HEADROOM_TAG_N}}.
   Confidence: HIGH = confirmed by a sampled fragment from the proxy stream
   and/or 1:1 with verbatim mode.jsx/briefing.jsx patterns by the same author;
   MED = strong inference from surrounding skeleton + design system; LOW = shape
   known, exact markup uncertain. NOT part of the verbatim source.

   TAG_0  [LOW]  Featured() body — the hero scan card (uses SCANS[0]). Renders a
                 Stage + render (HeroModel or ScanThumb), scan name/mode, stats,
                 and an open affordance; `big` => larger horizontal layout for
                 Pad/Mac. Exact markup not recoverable.
   TAG_1  [HIGH] <StatusBar />
   TAG_2  [MED]  <Ic name="settings" s={18} c={T.text2} />   (gear; onClick go('settings'))
   TAG_3  [MED]  <Ic name="search" s={17} c={T.text3} />
   TAG_4  [HIGH] <Featured scan={SCANS[0]} go={go} />
   TAG_5  [HIGH] <Filters active={filter} onPick={setFilter} />
   TAG_6  [HIGH] <ScanThumb scan={s} />                       (confirmed fragment)
   TAG_7  [MED]  Floating New-Scan dock — accent pill, e.g.
                 <Button kind="accent" size="lg" onClick={() => go('mode')}>
                   <Ic name="scan" s={18} c={T.onAccent} sw={2} /> New Scan</Button>
                 (possibly wrapped in <Glass>)
   TAG_8  [MED]  <Ic name="scan" s={18} c={T.onAccent} sw={2} />  (white logo on accent square)
   TAG_9  [MED]  <Ic name={r.i} s={17} c={r.on ? T.ink : T.text2} />
   TAG_10 [LOW]  divider after nav — likely <Rule style={{ margin: '8px 0' }} /> or spacer
   TAG_11 [LOW]  sidebar footer — storage indicator (Meter) or settings/profile button
   TAG_12 [HIGH] <PadStatusBar />
   TAG_13 [HIGH] <LibrarySidebar go={go} />                   (confirmed fragment)
   TAG_14 [MED]  <Ic name="search" s={18} c={T.text3} />
   TAG_15 [HIGH] <Ic name="scan" s={17} c={T.onAccent} sw={2} />   (confirmed fragment)
   TAG_16 [HIGH] <Featured scan={SCANS[0]} go={go} big />
   TAG_17 [MED]  <Filters />   (sampled "<Filters />" appears in the Recent header)
   TAG_18 [HIGH] <ScanThumb scan={s} />
   TAG_19 [HIGH] <LibrarySidebar go={go} mac />               (mac branch hides the logo row)
   TAG_20 [LOW]  toolbar accessory after "All Scans" title — count Chip / breadcrumb / Filters
   TAG_21 [MED]  <Ic name="search" s={14} c={T.text3} />
   TAG_22 [LOW]  <Ic name="open" s={14} c={T.onAccent} />     (Open button leading icon)
   TAG_23 [MED]  Mac hero band — <Featured scan={SCANS[0]} go={go} big />
   TAG_24 [MED]  <Filters />   ("See all"/filter affordance in Recent header)
   TAG_25 [HIGH] <ScanThumb scan={s} />                       (confirmed fragment)
   ============================================================================ */
