// studio/screens/mode.jsx — capture mode picker (Object · Space · Landscape · Auto-Pilot)

const MODES = [
  { id: 'auto',  name: 'Auto-Pilot', icon: 'sparkle', tag: 'CoreML scene analysis',
    sub: 'A vision model reads the live feed and selects the optimal mode for you.',
    specs: ['Adaptive', 'Recommended', 'No setup'], tint: '#2D68F0' },
  { id: 'object', name: 'Object', icon: 'cube', tag: 'Photogrammetry · ObjectCapture',
    sub: 'Hi-fidelity model of a single object. RealityKit-native, LiDAR-optional.',
    specs: ['LiDAR optional', '8K textures', '4–10 min'], tint: '#5B7E84' },
  { id: 'space', name: 'Space', icon: 'room', tag: 'RoomPlan · Parametric',
    sub: 'Structural blocks of rooms, walls, openings, furniture. LiDAR-required.',
    specs: ['LiDAR required', 'USDZ + walls', '2–5 min'], tint: '#7A6244' },
  { id: 'landscape', name: 'Landscape', icon: 'landscape', tag: 'ARKit VIO · GPS anchored',
    sub: 'Outdoor scenes where LiDAR is blinded by sun. Visual-inertial odometry.',
    specs: ['No LiDAR', 'GPS anchored', '6–20 min'], tint: '#4C5A60' },
];

function ModeTile({ mode, selected, onPick, big = false }) {
  return (
    <button className="st-tap" onClick={() => onPick(mode.id)} style={{
      position: 'relative', overflow: 'hidden', textAlign: 'left', cursor: 'pointer', width: '100%',
      borderRadius: big ? 22 : 18, padding: big ? 20 : 15,
      background: selected ? T.accentSoft : T.card,
      border: `0.5px solid ${selected ? T.accentLine : T.line}`,
      boxShadow: selected ? `0 0 0 1px ${T.accentLine}, ${T.cardShadow}` : T.cardShadow,
      display: 'flex', flexDirection: 'column', height: big ? '100%' : 'auto',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ width: big ? 48 : 40, height: big ? 48 : 40, borderRadius: big ? 14 : 12, background: selected ? T.accent : T.fieldFill, display: 'grid', placeItems: 'center', boxShadow: selected ? 'none' : `inset 0 0 0 0.5px ${T.line}` }}>
          <Ic name={mode.icon} s={big ? 24 : 20} c={selected ? T.onAccent : mode.tint} />
        </div>
        {selected && <Chip tone="accent" style={{ fontSize: 9 }}>SELECTED</Chip>}
      </div>
      <div style={{ fontSize: big ? 22 : 17, fontWeight: 700, letterSpacing: -0.4, color: T.ink, marginTop: big ? 14 : 10 }}>{mode.name}</div>
      <Label color={selected ? T.accentText : T.text3} style={{ marginTop: 4 }}>{mode.tag}</Label>
      {big && <div style={{ fontSize: 13, color: T.text2, marginTop: 8, lineHeight: 1.4 }}>{mode.sub}</div>}
      {big && (
        <div style={{ display: 'flex', gap: 6, marginTop: 'auto', paddingTop: 14, flexWrap: 'wrap' }}>
          {mode.specs.map(s => <Chip key={s} tone="neutral" style={{ fontSize: 11 }}>{s}</Chip>)}
        </div>
      )}
    </button>
  );
}

function PhoneModePicker({ go }) {
  const [sel, setSel] = React.useState('auto');
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <StatusBar />
      <div className="st-scroll" style={{ position: 'absolute', inset: 0, top: 54, overflow: 'auto', padding: '8px 20px 110px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button className="st-tap" onClick={() => go('library')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
          <Chip tone="neutral">Step 1 of 4</Chip>
          <button className="st-tap" onClick={() => go('library')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="close" s={16} c={T.text2} /></button>
        </div>
        <div style={{ marginTop: 18 }}>
          <Label>Choose capture</Label>
          <div style={{ fontSize: 30, fontWeight: 720, letterSpacing: -1, color: T.ink, marginTop: 6, lineHeight: 1.05 }}>What are you<br/>scanning today?</div>
          <div style={{ fontSize: 13.5, color: T.text2, marginTop: 8 }}>Auto-Pilot will pick for you — or choose a mode.</div>
        </div>
        <div style={{ marginTop: 18 }}><ModeTile mode={MODES[0]} big selected={sel === 'auto'} onPick={setSel} /></div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 12 }}>
          {MODES.slice(1).map(m => <ModeTile key={m.id} mode={m} selected={sel === m.id} onPick={setSel} />)}
        </div>
      </div>
      <div style={{ position: 'absolute', bottom: 28, left: 20, right: 20 }}>
        <Button kind="accent" full size="lg" onClick={() => go('briefing')}><Ic name={MODES.find(m => m.id === sel).icon} s={18} c={T.onAccent} /> {sel === 'auto' ? 'Start Auto-Pilot' : `Continue · ${MODES.find(m => m.id === sel).name}`}</Button>
      </div>
    </div>
  );
}

function StepTabs({ active }) {
  const steps = ['Mode', 'Briefing', 'Detail', 'Capture'];
  return (
    <div style={{ display: 'flex', gap: 6 }}>
      {steps.map((s, i) => {
        const on = i === active, done = i < active;
        return (
          <div key={s} style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '7px 13px', borderRadius: 10, background: on ? T.fieldFillHi : 'transparent', color: on ? T.ink : T.text3, fontSize: 13, fontWeight: on ? 650 : 500 }}>
            <span style={{ width: 16, height: 16, borderRadius: 99, display: 'grid', placeItems: 'center', background: done ? T.good : on ? T.accent : T.fieldFillHi, fontFamily: T.mono, fontSize: 9, fontWeight: 700, color: (done || on) ? '#fff' : T.text3 }}>{done ? '✓' : i + 1}</span>
            {s}
          </div>
        );
      })}
    </div>
  );
}

function PadModePicker({ go }) {
  const [sel, setSel] = React.useState('auto');
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <PadStatusBar />
      <div style={{ position: 'absolute', inset: 0, top: 30, display: 'flex', flexDirection: 'column', padding: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button className="st-tap" onClick={() => go('library')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
            <div><Label>New Scan · Step 1 of 4</Label><div style={{ fontSize: 17, fontWeight: 700, letterSpacing: -0.3, color: T.ink, marginTop: 2 }}>Choose capture mode</div></div>
          </div>
          <StepTabs active={0} />
          <button className="st-tap" onClick={() => go('library')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="close" s={16} c={T.text2} /></button>
        </div>
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 20, marginTop: 28, marginBottom: 22 }}>
          <div style={{ flex: 1 }}>
            <Label color={T.accentText}>3DSeen · Capture engine</Label>
            <div style={{ fontSize: 48, fontWeight: 730, letterSpacing: -2, color: T.ink, marginTop: 8, lineHeight: 1 }}>What are you scanning?</div>
            <div style={{ fontSize: 15, color: T.text2, marginTop: 12, maxWidth: 560, lineHeight: 1.45 }}>Auto-Pilot uses a CoreML vision model to read the scene and pick the optimal capture mode. Or pin a specific mode for full manual control.</div>
          </div>
          <Card radius={18} style={{ padding: 14, width: 280, display: 'flex', gap: 12, alignItems: 'center' }}>
            <div style={{ width: 56, height: 56, borderRadius: 14, overflow: 'hidden', position: 'relative', flexShrink: 0 }}><Stage radius={14}><HeroModel w={56} h={56} /></Stage></div>
            <div><Label>Live scene</Label><div style={{ fontSize: 14, fontWeight: 650, color: T.ink, marginTop: 3 }}>Object · table-top</div><div className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text3, marginTop: 2 }}>conf 92% · 1840 lux</div></div>
          </Card>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1.3fr 1fr 1fr 1fr', gap: 14, flex: 1, minHeight: 0 }}>
          {MODES.map(m => <ModeTile key={m.id} mode={m} big selected={sel === m.id} onPick={setSel} />)}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 20 }}>
          <div style={{ display: 'flex', gap: 28 }}>
            {[['Device','iPad Pro M4 · LiDAR'],['Thermal','Nominal · 31°C'],['Storage','244.6 GB free']].map(([k,v]) => (
              <div key={k}><Label>{k}</Label><div style={{ fontSize: 13.5, fontWeight: 600, color: T.ink, marginTop: 3 }}>{v}</div></div>
            ))}
          </div>
          <Button kind="accent" size="lg" onClick={() => go('briefing')}><Ic name={MODES.find(m => m.id === sel).icon} s={18} c={T.onAccent} /> Continue with {MODES.find(m => m.id === sel).name}</Button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneModePicker, PadModePicker, MODES, StepTabs });
