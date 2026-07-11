// studio/screens/export.jsx — file output flow: config → progress → done
// Sheet on iPhone/iPad, full workspace on Mac. The "modal/screen for outputting files".

const DESTINATIONS = [
  { id: 'air',    l: 'AirDrop',    i: 'airdrop' },
  { id: 'mac',    l: "Adam's MBP", i: 'laptop' },
  { id: 'icloud', l: 'iCloud',     i: 'cloud' },
  { id: 'files',  l: 'Files',      i: 'folder' },
];

const EXPORT_OPTIONS = [
  { id: 'measure', l: 'Include measurements (3 pins)', on: true },
  { id: 'bake', l: 'Bake materials to 2K', on: false },
  { id: 'scale', l: 'Scale to scene · 1.0×', on: true },
  { id: 'color', l: 'Color-managed (Display P3)', on: true },
];

function useExportFlow() {
  const [stage, setStage] = React.useState('config'); // config | progress | done
  const [fmt, setFmt] = React.useState('usdz');
  const [dest, setDest] = React.useState('air');
  const [opts, setOpts] = React.useState(() => Object.fromEntries(EXPORT_OPTIONS.map(o => [o.id, o.on])));
  const [pct, setPct] = React.useState(0);
  const timer = React.useRef(null);
  const start = () => {
    setStage('progress'); setPct(0);
    timer.current = setInterval(() => {
      setPct(p => {
        const np = p + Math.random() * 9 + 3;
        if (np >= 100) { clearInterval(timer.current); setTimeout(() => setStage('done'), 360); return 100; }
        return np;
      });
    }, 180);
  };
  const reset = () => { clearInterval(timer.current); setStage('config'); setPct(0); };
  React.useEffect(() => () => clearInterval(timer.current), []);
  const format = EXPORT_FORMATS.find(f => f.id === fmt);
  return { stage, fmt, setFmt, dest, setDest, opts, setOpts, pct, start, reset, format };
}

function FormatRow({ f, on, onPick }) {
  return (
    <button className="st-tap" onClick={() => onPick(f.id)} style={{
      width: '100%', display: 'flex', alignItems: 'center', gap: 12, padding: 12, borderRadius: 14, border: 'none', cursor: 'pointer', textAlign: 'left',
      background: on ? T.accentSoft : T.fieldFill, boxShadow: on ? `inset 0 0 0 1px ${T.accentLine}` : `inset 0 0 0 0.5px ${T.line}`,
    }}>
      <div style={{ width: 40, height: 40, borderRadius: 10, flexShrink: 0, display: 'grid', placeItems: 'center', background: on ? T.accent : T.card, boxShadow: on ? 'none' : `inset 0 0 0 0.5px ${T.line}` }}>
        <span style={{ fontSize: 11.5, fontWeight: 800, letterSpacing: -0.2, color: on ? T.onAccent : T.text2 }}>{f.name}</span>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span className="st-num" style={{ fontSize: 14, fontWeight: 650, color: T.ink, fontFamily: T.mono }}>{f.ext}</span>
          {f.best && <Chip tone="accent" style={{ fontSize: 9, padding: '2px 6px' }}>BEST</Chip>}
        </div>
        <div style={{ fontSize: 11.5, color: T.text3, marginTop: 2 }}>{f.desc}</div>
      </div>
      <span className="st-num" style={{ fontFamily: T.mono, fontSize: 12, color: T.text2 }}>{f.size}</span>
      <div style={{ width: 20, height: 20, borderRadius: 99, display: 'grid', placeItems: 'center', background: on ? T.accent : 'transparent', boxShadow: on ? 'none' : `inset 0 0 0 1.5px ${T.line}` }}>
        {on && <Ic name="check" s={13} c={T.onAccent} sw={2.6} />}
      </div>
    </button>
  );
}

function DestRow({ value, onChange }) {
  return (
    <div style={{ display: 'flex', gap: 12 }}>
      {DESTINATIONS.map(d => {
        const on = d.id === value;
        return (
          <button key={d.id} className="st-tap" onClick={() => onChange(d.id)} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, border: 'none', background: 'transparent', cursor: 'pointer' }}>
            <div style={{ width: 56, height: 56, borderRadius: 18, display: 'grid', placeItems: 'center', background: on ? T.accent : T.fieldFill, boxShadow: on ? `0 4px 14px ${T.accentSoft}` : `inset 0 0 0 0.5px ${T.line}` }}>
              <Ic name={d.i} s={24} c={on ? T.onAccent : T.text2} />
            </div>
            <span style={{ fontSize: 11.5, fontWeight: on ? 650 : 500, color: on ? T.ink : T.text2 }}>{d.l}</span>
          </button>
        );
      })}
    </div>
  );
}

function ProgressView({ pct, format, dest, big = false }) {
  const d = DESTINATIONS.find(x => x.id === dest);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: big ? 22 : 16, padding: big ? '20px 0' : '8px 0' }}>
      <Ring value={pct / 100} size={big ? 132 : 104} stroke={big ? 9 : 8} label={Math.round(pct)} sub="%" />
      <div style={{ textAlign: 'center' }}>
        <div style={{ fontSize: big ? 20 : 16, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Exporting {format.name}…</div>
        <div className="st-num" style={{ fontSize: 13, color: T.text2, marginTop: 4 }}>
          {pct < 40 ? 'Triangulating mesh' : pct < 75 ? 'Packing 4K textures' : 'Writing ' + format.ext} · {format.size}
        </div>
      </div>
      <Chip tone="neutral"><Ic name={d.i} s={14} c={T.text2} /> to {d.l}</Chip>
    </div>
  );
}

function DoneView({ format, dest, onAgain, go, big = false }) {
  const d = DESTINATIONS.find(x => x.id === dest);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: big ? 20 : 14, padding: big ? '20px 0' : '8px 0' }} className="st-rise-in">
      <div style={{ width: big ? 84 : 68, height: big ? 84 : 68, borderRadius: 99, background: T.goodSoft, display: 'grid', placeItems: 'center' }}>
        <div style={{ width: big ? 56 : 46, height: big ? 56 : 46, borderRadius: 99, background: T.good, display: 'grid', placeItems: 'center' }}><Ic name="check" s={big ? 30 : 24} c="#fff" sw={2.6} /></div>
      </div>
      <div style={{ textAlign: 'center' }}>
        <div style={{ fontSize: big ? 22 : 18, fontWeight: 720, letterSpacing: -0.4, color: T.ink }}>Export complete</div>
        <div className="st-num" style={{ fontSize: 13.5, color: T.text2, marginTop: 5 }}>Celestial Bust{format.ext} · {format.size} · sent to {d.l}</div>
      </div>
      <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
        <Button kind="secondary" onClick={onAgain}><Ic name="refresh" s={15} c={T.ink} /> Export again</Button>
        <Button kind="accent" onClick={() => go('library')}><Ic name="check" s={15} c={T.onAccent} /> Done</Button>
      </div>
    </div>
  );
}

function ModelBadge({ size = 50 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: 12, overflow: 'hidden', position: 'relative', flexShrink: 0, boxShadow: `inset 0 0 0 0.5px ${T.line}` }}>
      <Stage radius={12}><HeroModel w={size} h={size} /></Stage>
    </div>
  );
}

// ─── iPhone (bottom sheet) ──────────────────────────────────────────
function PhoneExport({ go }) {
  const x = useExportFlow();
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <Stage><HeroModel w={402} h={500} /></Stage>
      <div style={{ position: 'absolute', inset: 0, background: T.mode === 'dark' ? 'rgba(0,0,0,0.45)' : 'rgba(20,20,30,0.28)' }} />
      <StatusBar />
      {/* sheet */}
      <div className="st-sheet-in" style={{ position: 'absolute', left: 0, right: 0, bottom: 0 }}>
        <Glass radius={30} style={{ borderBottomLeftRadius: 0, borderBottomRightRadius: 0, padding: '12px 18px 34px' }}>
          <div style={{ width: 38, height: 5, borderRadius: 99, background: T.lineStrong, margin: '0 auto 14px' }} />
          {x.stage === 'config' && <>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <ModelBadge />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 17, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Export Celestial Bust</div>
                <div className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3, marginTop: 2 }}>FULL · 4.2M tris · 184 MB</div>
              </div>
              <button className="st-tap" onClick={() => go('viewer')} style={{ width: 32, height: 32, borderRadius: 99, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="close" s={15} c={T.text2} /></button>
            </div>
            <Label style={{ marginTop: 18, marginBottom: 10 }}>Send to</Label>
            <DestRow value={x.dest} onChange={x.setDest} />
            <Label style={{ marginTop: 18, marginBottom: 10 }}>Format</Label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {EXPORT_FORMATS.slice(0, 3).map(f => <FormatRow key={f.id} f={f} on={x.fmt === f.id} onPick={x.setFmt} />)}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2, marginTop: 14 }}>
              {EXPORT_OPTIONS.slice(0, 2).map(o => (
                <div key={o.id} style={{ display: 'flex', alignItems: 'center', padding: '8px 2px' }}>
                  <span style={{ flex: 1, fontSize: 13.5, color: T.ink, fontWeight: 500 }}>{o.l}</span>
                  <Toggle on={x.opts[o.id]} onChange={v => x.setOpts(s => ({ ...s, [o.id]: v }))} />
                </div>
              ))}
            </div>
            <div style={{ marginTop: 16 }}>
              <Button kind="accent" full size="lg" onClick={x.start}><Ic name="export" s={17} c={T.onAccent} /> Export {x.format.name} · {x.format.size}</Button>
            </div>
          </>}
          {x.stage === 'progress' && <ProgressView pct={x.pct} format={x.format} dest={x.dest} />}
          {x.stage === 'done' && <DoneView format={x.format} dest={x.dest} onAgain={x.reset} go={go} />}
        </Glass>
      </div>
    </div>
  );
}

// ─── iPad (centered modal) ──────────────────────────────────────────
function PadExport({ go }) {
  const x = useExportFlow();
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <Stage><HeroModel w={1194} h={834} /></Stage>
      <div style={{ position: 'absolute', inset: 0, background: T.mode === 'dark' ? 'rgba(0,0,0,0.5)' : 'rgba(20,20,30,0.32)' }} />
      <PadStatusBar tone="light" />
      <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', padding: 40 }}>
        <Glass radius={26} className="st-modal-in" style={{ width: 880, maxWidth: '100%', padding: 0, overflow: 'hidden' }}>
          {/* header */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '16px 22px', borderBottom: `0.5px solid ${T.line}` }}>
            <ModelBadge size={44} />
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 17, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Export & Share</div>
              <div className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3 }}>CELESTIAL BUST · FULL · 184 MB</div>
            </div>
            <button className="st-tap" onClick={() => go('viewer')} style={{ width: 34, height: 34, borderRadius: 99, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="close" s={16} c={T.text2} /></button>
          </div>
          {x.stage === 'config' ? (
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', minHeight: 420 }}>
              {/* left: preview + dest */}
              <div style={{ padding: 22, borderRight: `0.5px solid ${T.line}`, display: 'flex', flexDirection: 'column' }}>
                <div style={{ flex: 1, borderRadius: 18, overflow: 'hidden', position: 'relative', minHeight: 200 }}>
                  <Stage radius={18}><HeroModel w={400} h={300} /></Stage>
                  <div style={{ position: 'absolute', top: 14, right: 14 }}><Chip tone="accent"><Ic name="scan" s={13} c={T.accentText} /> AR Quick Look ready</Chip></div>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 12, marginTop: 16 }}>
                  <Stat k="Format" v={x.format.name} c={T.accentText} size="sm" /><Stat k="Size" v={x.format.size.split(' ')[0]} unit="MB" size="sm" /><Stat k="Tris" v="4.2M" size="sm" /><Stat k="Tex" v="4K" size="sm" />
                </div>
                <Label style={{ marginTop: 18, marginBottom: 10 }}>Send to</Label>
                <DestRow value={x.dest} onChange={x.setDest} />
              </div>
              {/* right: format + options */}
              <div className="st-scroll" style={{ padding: 22, overflow: 'auto', display: 'flex', flexDirection: 'column' }}>
                <Label style={{ marginBottom: 10 }}>Format</Label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {EXPORT_FORMATS.map(f => <FormatRow key={f.id} f={f} on={x.fmt === f.id} onPick={x.setFmt} />)}
                </div>
                <Label style={{ marginTop: 18, marginBottom: 6 }}>Options</Label>
                <div>
                  {EXPORT_OPTIONS.map(o => (
                    <div key={o.id} style={{ display: 'flex', alignItems: 'center', padding: '9px 2px', borderTop: o.id !== 'measure' ? `0.5px solid ${T.line}` : 'none' }}>
                      <span style={{ flex: 1, fontSize: 13.5, color: T.ink, fontWeight: 500 }}>{o.l}</span>
                      <Toggle on={x.opts[o.id]} onChange={v => x.setOpts(s => ({ ...s, [o.id]: v }))} />
                    </div>
                  ))}
                </div>
                <div style={{ flex: 1 }} />
                <div style={{ marginTop: 18 }}>
                  <Button kind="accent" full size="lg" onClick={x.start}><Ic name="export" s={17} c={T.onAccent} /> Export {x.format.name} · {x.format.size}</Button>
                </div>
              </div>
            </div>
          ) : (
            <div style={{ minHeight: 420, display: 'grid', placeItems: 'center' }}>
              {x.stage === 'progress' ? <ProgressView pct={x.pct} format={x.format} dest={x.dest} big /> : <DoneView format={x.format} dest={x.dest} onAgain={x.reset} go={go} big />}
            </div>
          )}
        </Glass>
      </div>
    </div>
  );
}

// ─── Mac (workspace) ────────────────────────────────────────────────
function MacExport({ go }) {
  const x = useExportFlow();
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, display: 'flex', flexDirection: 'column' }}>
      <div style={{ height: 52, flexShrink: 0, borderBottom: `0.5px solid ${T.line}`, display: 'flex', alignItems: 'center', gap: 14, padding: '0 18px 0 84px', background: T.card2 }}>
        <button className="st-tap" onClick={() => go('viewer')} style={{ height: 30, padding: '0 10px', borderRadius: 8, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 600, color: T.text2 }}><Ic name="back" s={15} c={T.text2} /> Model</button>
        <Rule vertical style={{ height: 22 }} />
        <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Export · Celestial Bust</div>
        <div style={{ flex: 1 }} />
        <Chip tone="neutral"><Ic name="layers" s={13} c={T.text2} /> 6 formats</Chip>
      </div>
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {/* preview */}
        <div style={{ flex: 1, position: 'relative', minWidth: 0, borderRight: `0.5px solid ${T.line}` }}>
          <Stage><HeroModel w={620} h={620} material={x.fmt === 'ply' ? 'wire' : 'pbr'} /></Stage>
          <div style={{ position: 'absolute', top: 18, left: 18 }}><Chip tone="accent"><Ic name="scan" s={13} c={T.accentText} /> AR Quick Look ready</Chip></div>
          <div style={{ position: 'absolute', bottom: 18, left: '50%', transform: 'translateX(-50%)' }}>
            <Glass radius={16} style={{ padding: '12px 18px', display: 'flex', gap: 26 }}>
              <Stat k="Format" v={x.format.name} c={T.accentText} size="sm" /><Stat k="Size" v={x.format.size.split(' ')[0]} unit="MB" size="sm" /><Stat k="Triangles" v="4.2M" size="sm" /><Stat k="Textures" v="4K PBR" size="sm" />
            </Glass>
          </div>
        </div>
        {/* config panel */}
        <div className="st-scroll" style={{ width: 380, flexShrink: 0, background: T.card2, overflow: 'auto', padding: 22, display: 'flex', flexDirection: 'column' }}>
          {x.stage === 'config' && <>
            <Label style={{ marginBottom: 10 }}>Format</Label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {EXPORT_FORMATS.map(f => <FormatRow key={f.id} f={f} on={x.fmt === f.id} onPick={x.setFmt} />)}
            </div>
            <Label style={{ marginTop: 20, marginBottom: 6 }}>Options</Label>
            <div>
              {EXPORT_OPTIONS.map(o => (
                <div key={o.id} style={{ display: 'flex', alignItems: 'center', padding: '9px 2px', borderTop: o.id !== 'measure' ? `0.5px solid ${T.line}` : 'none' }}>
                  <span style={{ flex: 1, fontSize: 13.5, color: T.ink, fontWeight: 500 }}>{o.l}</span>
                  <Toggle on={x.opts[o.id]} onChange={v => x.setOpts(s => ({ ...s, [o.id]: v }))} />
                </div>
              ))}
            </div>
            <Label style={{ marginTop: 20, marginBottom: 10 }}>Destination</Label>
            <DestRow value={x.dest} onChange={x.setDest} />
            <div style={{ flex: 1 }} />
            <div style={{ marginTop: 22 }}>
              <Button kind="accent" full size="lg" onClick={x.start}><Ic name="export" s={17} c={T.onAccent} /> Export {x.format.name} · {x.format.size}</Button>
              <div style={{ textAlign: 'center', marginTop: 10 }}><span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3 }}>~/Exports/3DSeen/celestial-bust{x.format.ext}</span></div>
            </div>
          </>}
          {x.stage === 'progress' && <div style={{ flex: 1, display: 'grid', placeItems: 'center' }}><ProgressView pct={x.pct} format={x.format} dest={x.dest} big /></div>}
          {x.stage === 'done' && <div style={{ flex: 1, display: 'grid', placeItems: 'center' }}><DoneView format={x.format} dest={x.dest} onAgain={x.reset} go={go} big /></div>}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneExport, PadExport, MacExport });
