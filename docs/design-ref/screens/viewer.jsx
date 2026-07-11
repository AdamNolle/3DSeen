// studio/screens/viewer.jsx — finished 3D model viewer (iPhone · iPad · Mac)
//
// ⚠️ FIDELITY NOTE — READ BEFORE USING AS GROUND TRUTH ⚠️
// The DesignSync proxy returned this single file ONLY in a lossy-compressed form
// ("1077 items compressed to 51"). The proxy preserved the full *template*
// (all layout containers, every literal copy string, all numeric metrics, the
// MATERIALS/MEASUREMENTS data wiring, the Mac tool-rail array, the <Segmented>
// options) but DROPPED the contents of ~46 inner expression slots (originally
// emitted as {{HEADROOM_TAG_n}}). Only a 51-fragment inline sample of those
// slots survived. Below, slots are reconstructed:
//   • [VERBATIM]      = recovered exactly from the surviving inline sample.
//   • [PATTERN]       = reconstructed from the identical idioms in the verbatim
//                       compute.jsx / export.jsx (same toolbar, Stage, Stat,
//                       Chip, Rule, MaterialPicker patterns) — structure certain,
//                       a prop value may differ.
//   • [INFERRED]      = best-guess content for a slot with no surviving sample;
//                       layout position is verbatim, inner detail is approximate.
// Everything OUTSIDE the marked slots is verbatim. See viewer.md for the
// authoritative, per-slot confidence spec.

const MATERIALS = [
  { id: 'pbr',   l: 'PBR',     g: ['#BFA98C', '#6B5C49'] },
  { id: 'matte', l: 'Matte',   g: ['#E2D8C6', '#8B7B62'] },
  { id: 'metal', l: 'Metal',   g: ['#E8E6E2', '#5A5E63'] },
  { id: 'wire',  l: 'Wire',    g: ['#9BC0FF', '#2D68F0'] },
];

function ToolRail({ items, active, onPick, vertical = true, labels = false }) {
  return (
    // [INFERRED] glass pill rail; on Phone vertical icons-only, on Pad vertical with labels
    <Glass radius={vertical ? 18 : 999} style={{ padding: 6, display: 'flex', flexDirection: vertical ? 'column' : 'row', gap: 4 }}>
      {items.map(it => {
        const on = it.id === active;
        return (
          <button key={it.id} className="st-tap" onClick={() => onPick(it.id)} style={{ width: 44, height: labels ? 50 : 44, borderRadius: 13, border: 'none', cursor: 'pointer', background: on ? T.accent : 'transparent', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3 }}>
            <Ic name={it.i} s={20} c={on ? T.onAccent : T.text2} />
            {labels && <span style={{ fontSize: 9, fontWeight: 600, color: on ? T.onAccent : T.text3 }}>{it.l}</span>}
          </button>
        );
      })}
    </Glass>
  );
}

function MaterialPicker({ value, onChange, compact = false }) {
  return (
    <div style={{ display: 'flex', gap: 6 }}>
      {MATERIALS.map(m => {
        const on = m.id === value;
        return (
          <button key={m.id} className="st-tap" onClick={() => onChange(m.id)} style={{
            flex: 1, padding: compact ? '7px 4px' : '9px 6px', borderRadius: 14, border: 'none', cursor: 'pointer',
            background: on ? T.fieldFillHi : 'transparent', boxShadow: on ? `inset 0 0 0 1px ${T.accentLine}` : 'none',
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
          }}>
            <div style={{ width: 30, height: 30, borderRadius: 99, background: `radial-gradient(circle at 32% 28%, ${m.g[0]}, ${m.g[1]})`, boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.5)' }} />
            <span style={{ fontSize: 10.5, fontWeight: on ? 700 : 500, color: on ? T.ink : T.text3 }}>{m.l}</span>
          </button>
        );
      })}
    </div>
  );
}

// measurement overlay lines for the bust (viewBox-relative)
function MeasureOverlay({ vb, lines }) {
  return (
    <svg width="100%" height="100%" viewBox={vb} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      {lines.map((l, i) => (
        // [INFERRED] dashed accent leader line with end-caps
        <g key={i}>
          <line x1={l.x1} y1={l.y1} x2={l.x2} y2={l.y2} stroke={T.accent} strokeWidth="1.5" strokeDasharray="4 3" />
          <circle cx={l.x1} cy={l.y1} r="3" fill={T.accent} />
          <circle cx={l.x2} cy={l.y2} r="3" fill={T.accent} />
        </g>
      ))}
    </svg>
  );
}

// ─── iPhone ─────────────────────────────────────────────────────────
function PhoneViewer({ go }) {
  const [mat, setMat] = React.useState('pbr');
  const [tool, setTool] = React.useState('orbit');
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {/* [PATTERN] full-bleed stage with the finished model */}
      <Stage><HeroModel w={402} h={874} material={mat} /></Stage>
      {/* [INFERRED] top/bottom legibility scrim over the stage */}
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, rgba(0,0,0,0.20), transparent 26%, transparent 72%, rgba(0,0,0,0.24))', pointerEvents: 'none' }} />
      {/* [PATTERN] status bar in light tone over the dark stage */}
      <StatusBar tone="light" />
      {/* top bar */}
      <div style={{ position: 'absolute', top: 56, left: 14, right: 14, display: 'flex', alignItems: 'center', gap: 8 }}>
        <button className="st-tap" onClick={() => go('library')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.glassFill, backdropFilter: 'blur(18px)', WebkitBackdropFilter: 'blur(18px)', boxShadow: T.glassShadow, display: 'grid', placeItems: 'center' }}>{/* [VERBATIM] */}<Ic name="back" s={18} c={T.ink} /></button>
        {/* [INFERRED] centered glass title pill */}
        <Glass radius={999} style={{ flex: 1, padding: '9px 14px', textAlign: 'center' }}><span style={{ fontSize: 14, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Celestial Bust</span></Glass>
        <button className="st-tap" onClick={() => go('export')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.glassFill, backdropFilter: 'blur(18px)', WebkitBackdropFilter: 'blur(18px)', boxShadow: T.glassShadow, display: 'grid', placeItems: 'center' }}>{/* [INFERRED] */}<Ic name="export" s={18} c={T.ink} /></button>
      </div>
      {/* tool rail */}
      <div style={{ position: 'absolute', top: 110, right: 14 }}>
        {/* [INFERRED] vertical icon rail */}
        <ToolRail items={[{ id: 'orbit', i: 'cube' }, { id: 'measure', i: 'ruler' }, { id: 'pin', i: 'pin' }, { id: 'light', i: 'light' }]} active={tool} onPick={setTool} />
      </div>
      {tool === 'measure' && (
        <div style={{ position: 'absolute', left: 52, top: 326 }}>
          {/* [VERBATIM] measurement value callout */}
          <Glass radius={10} style={{ padding: '5px 10px' }}><span className="st-num" style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 700, color: T.accentText }}>14.20 cm</span></Glass>
        </div>
      )}
      {/* bottom inspector */}
      <div style={{ position: 'absolute', bottom: 26, left: 14, right: 14, display: 'flex', flexDirection: 'column', gap: 8 }}>
        {/* [VERBATIM] stats + material card */}
        <Glass radius={22} style={{ padding: 14 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
            <Label color={T.good}>Captured today · Object · Full</Label>
            <span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3 }}>v2</span>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8, marginTop: 12 }}>
            <Stat k="Tris" v="4.2M" size="sm" /><Stat k="Tex" v="4K" size="sm" /><Stat k="PSNR" v="38.7" size="sm" /><Stat k="Scale" v="14cm" size="sm" />
          </div>
          <div style={{ marginTop: 12 }}><MaterialPicker value={mat} onChange={setMat} compact /></div>
        </Glass>
        <div style={{ display: 'flex', gap: 8 }}>
          <Button kind="glass" style={{ flex: 1 }}>{/* [VERBATIM] */}<Ic name="scan" s={16} c={T.ink} /> AR</Button>
          <Button kind="accent" style={{ flex: 1.5 }} onClick={() => go('export')}>{/* [VERBATIM] */}<Ic name="export" s={16} c={T.onAccent} /> Export</Button>
        </div>
      </div>
    </div>
  );
}

// ─── iPad ───────────────────────────────────────────────────────────
function PadViewer({ go }) {
  const [mat, setMat] = React.useState('pbr');
  const [tool, setTool] = React.useState('orbit');
  const [env, setEnv] = React.useState('Studio');
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {/* [PATTERN] full-bleed stage */}
      <Stage><HeroModel w={1194} h={834} material={mat} /></Stage>
      {/* [INFERRED] legibility scrim */}
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, rgba(0,0,0,0.16), transparent 22%, transparent 74%, rgba(0,0,0,0.20))', pointerEvents: 'none' }} />
      {/* [PATTERN] status bar */}
      <PadStatusBar tone="light" />
      {/* top bar */}
      <div style={{ position: 'absolute', top: 36, left: 18, right: 18, display: 'flex', alignItems: 'center', gap: 10 }}>
        <button className="st-tap" onClick={() => go('library')} style={{ width: 40, height: 40, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.glassFill, backdropFilter: 'blur(18px)', WebkitBackdropFilter: 'blur(18px)', boxShadow: T.glassShadow, display: 'grid', placeItems: 'center' }}>{/* [VERBATIM] */}<Ic name="back" s={18} c={T.ink} /></button>
        {/* [INFERRED] glass title pill */}
        <Glass radius={999} style={{ padding: '9px 16px' }}><span style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Celestial Bust</span></Glass>
        {/* [INFERRED] meta chip */}
        <Glass radius={999} style={{ padding: '7px 12px' }}><span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text2 }}>FULL · 4.2M · 184 MB</span></Glass>
        <div style={{ flex: 1 }} />
        <Button kind="glass" size="sm">{/* [INFERRED] */}<Ic name="airdrop" s={15} c={T.ink} /> AirDrop</Button>
        <Button kind="accent" size="sm" onClick={() => go('export')}>{/* [INFERRED] */}<Ic name="export" s={15} c={T.onAccent} /> Export</Button>
      </div>
      {/* left tool rail */}
      <div style={{ position: 'absolute', top: 96, left: 18 }}>
        {/* [INFERRED] vertical labeled rail */}
        <ToolRail items={[{ id: 'orbit', i: 'cube', l: 'Orbit' }, { id: 'measure', i: 'ruler', l: 'Measure' }, { id: 'pin', i: 'pin', l: 'Pin' }, { id: 'light', i: 'light', l: 'Light' }, { id: 'ar', i: 'scan', l: 'AR' }]} active={tool} onPick={setTool} labels />
      </div>
      {tool === 'measure' && <>
        <div style={{ position: 'absolute', left: 358, top: 350 }}>{/* [VERBATIM pattern] */}<Glass radius={10} style={{ padding: '5px 10px' }}><span className="st-num" style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 700, color: T.accentText }}>14.20 cm</span></Glass></div>
        <div style={{ position: 'absolute', left: 700, top: 305 }}>{/* [INFERRED pattern] */}<Glass radius={10} style={{ padding: '5px 10px' }}><span className="st-num" style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 700, color: T.accentText }}>21.8 cm</span></Glass></div>
      </>}
      {/* right inspector */}
      <div style={{ position: 'absolute', top: 96, right: 18, bottom: 18, width: 326, display: 'flex', flexDirection: 'column', gap: 12 }}>
        {/* [INFERRED] geometry card */}
        <Glass radius={20} style={{ padding: 16 }}>
          <Label color={T.accentText}>Geometry</Label>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginTop: 12 }}>
            <Stat k="Triangles" v="4.2M" size="sm" /><Stat k="Vertices" v="2.1M" size="sm" /><Stat k="Textures" v="4K PBR" size="sm" /><Stat k="PSNR" v="38.7" size="sm" />
          </div>
        </Glass>
        {/* [INFERRED] material card */}
        <Glass radius={20} style={{ padding: 16 }}>
          <Label>Material override</Label>
          <div style={{ marginTop: 12 }}><MaterialPicker value={mat} onChange={setMat} /></div>
        </Glass>
        {/* [INFERRED] measurements card */}
        <Glass radius={20} style={{ padding: 16, flex: 1, minHeight: 0 }}>
          <Label color={T.good}>Measurements · 3 pins</Label>
          <div style={{ marginTop: 10 }}>
            {MEASUREMENTS.map(m => (
              <div key={m.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0', borderTop: m.id !== 'M01' ? `0.5px solid ${T.line}` : 'none' }}>
                <span style={{ flex: 1, fontSize: 13, color: T.text2 }}>{m.l}</span>
                <span className="st-num" style={{ fontSize: 14, fontWeight: 700, color: T.ink }}>{m.v} {m.u}</span>
              </div>
            ))}
          </div>
        </Glass>
      </div>
      {/* bottom env bar */}
      <div style={{ position: 'absolute', bottom: 18, left: 110, right: 360, display: 'flex', justifyContent: 'center' }}>
        {/* [INFERRED] environment / lighting selector */}
        <Glass radius={999} style={{ padding: 6 }}><Segmented size="sm" options={['Studio', 'Sunset', 'Soft', 'Field']} value={env} onChange={setEnv} /></Glass>
      </div>
    </div>
  );
}

// ─── Mac ────────────────────────────────────────────────────────────
function MacViewer({ go }) {
  const [mat, setMat] = React.useState('pbr');
  const [tool, setTool] = React.useState('orbit');
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, display: 'flex', flexDirection: 'column' }}>
      {/* toolbar */}
      <div style={{ height: 52, flexShrink: 0, borderBottom: `0.5px solid ${T.line}`, display: 'flex', alignItems: 'center', gap: 14, padding: '0 18px 0 84px', background: T.card2 }}>
        <button className="st-tap" onClick={() => go('library')} style={{ height: 30, padding: '0 10px', borderRadius: 8, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 600, color: T.text2 }}>{/* [VERBATIM] */}<Ic name="back" s={15} c={T.text2} /> Library</button>
        {/* [PATTERN] */}<Rule vertical style={{ height: 22 }} />
        <span style={{ width: 8, height: 8, borderRadius: 99, background: T.good }} />
        <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Celestial Bust</div>
        <span className="st-num" style={{ fontFamily: T.mono, fontSize: 12, color: T.text3 }}>FULL · 4.2M · 184 MB</span>
        <div style={{ flex: 1 }} />
        <Segmented size="sm" options={['Inspect','AR','Compare','Slice']} value="Inspect" onChange={() => {}} />
        <Button kind="ghost" size="sm">{/* [VERBATIM] */}<Ic name="airdrop" s={15} c={T.text2} /> AirDrop</Button>
        <Button kind="accent" size="sm" onClick={() => go('export')}>{/* [VERBATIM] */}<Ic name="export" s={15} c={T.onAccent} /> Export…</Button>
      </div>
      {/* body */}
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {/* tool rail */}
        <div style={{ width: 64, flexShrink: 0, borderRight: `0.5px solid ${T.line}`, background: T.card2, display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '14px 0', gap: 4 }}>
          {[{ id: 'orbit', i: 'cube' }, { id: 'measure', i: 'ruler' }, { id: 'pin', i: 'pin' }, { id: 'layers', i: 'layers' }, { id: 'light', i: 'light' }, { id: 'ar', i: 'scan' }, { id: 'slice', i: 'focus' }].map(it => {
            const on = it.id === tool;
            return <button key={it.id} className="st-tap" onClick={() => setTool(it.id)} style={{ width: 42, height: 42, borderRadius: 11, border: 'none', cursor: 'pointer', background: on ? T.accent : 'transparent', display: 'grid', placeItems: 'center' }}>{/* [VERBATIM] */}<Ic name={it.i} s={20} c={on ? T.onAccent : T.text2} /></button>;
          })}
        </div>
        {/* stage */}
        <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
          {/* [PATTERN] */}<Stage><HeroModel w={620} h={620} material={mat} /></Stage>
          {/* [INFERRED] top-left status chip */}
          <div style={{ position: 'absolute', top: 18, left: 18 }}><Chip tone="neutral"><Ic name="cube" s={13} c={T.text2} /> Orbit · ⌘-drag to pan</Chip></div>
          {/* floating env bar */}
          <div style={{ position: 'absolute', bottom: 20, left: '50%', transform: 'translateX(-50%)' }}>
            {/* [INFERRED] environment selector */}
            <Glass radius={16} style={{ padding: 6 }}><Segmented size="sm" options={['Studio', 'Sunset', 'Soft', 'Field']} value="Studio" onChange={() => {}} /></Glass>
          </div>
        </div>
        {/* inspector */}
        <div className="st-scroll" style={{ width: 320, flexShrink: 0, borderLeft: `0.5px solid ${T.line}`, background: T.card2, overflow: 'auto', padding: 18, display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div>
            <Label color={T.accentText}>Geometry</Label>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginTop: 12 }}>
              {/* [INFERRED] x4 geometry stats */}
              <Stat k="Triangles" v="4.2M" size="sm" /><Stat k="Vertices" v="2.1M" size="sm" /><Stat k="Textures" v="4K PBR" size="sm" /><Stat k="File size" v="184 MB" size="sm" />
            </div>
          </div>
          {/* [PATTERN] */}<Rule />
          <div>
            <Label>Material override</Label>
            <div style={{ marginTop: 12 }}>{/* [PATTERN] */}<MaterialPicker value={mat} onChange={setMat} /></div>
          </div>
          {/* [PATTERN] */}<Rule />
          <div>
            <Label color={T.good}>Measurements · 3 pins</Label>
            <div style={{ marginTop: 10 }}>
              {MEASUREMENTS.map(m => (
                <div key={m.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0', borderTop: m.id !== 'M01' ? `0.5px solid ${T.line}` : 'none' }}>
                  {/* [INFERRED] pin index dot */}
                  <span className="st-num" style={{ width: 20, height: 20, borderRadius: 99, flexShrink: 0, display: 'grid', placeItems: 'center', background: T.accentSoft, color: T.accentText, fontSize: 10, fontWeight: 700 }}>{m.id.replace(/\D/g, '')}</span>
                  <span style={{ flex: 1, fontSize: 13, color: T.text2 }}>{m.l}</span>
                  <span className="st-num" style={{ fontSize: 14, fontWeight: 700, color: T.ink }}>{m.v} {m.u}</span>
                </div>
              ))}
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
              <Button kind="secondary" size="sm" style={{ flex: 1 }}>{/* [VERBATIM] */}<Ic name="plus" s={15} c={T.ink} /> Add pin</Button>
              <Button kind="secondary" size="sm" style={{ flex: 1 }}>{/* [VERBATIM] */}<Ic name="download" s={15} c={T.ink} /> CSV</Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneViewer, PadViewer, MacViewer, MATERIALS });
