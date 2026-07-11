// studio/screens/briefing.jsx — pre-capture briefing & guidance

const CHECKLIST = [
  { id: 'light', label: 'Even, diffuse lighting', status: 'pass', detail: '1842 lux measured', i: 'light' },
  { id: 'reflect', label: 'Reflective surfaces detected', status: 'warn', detail: '2 glossy regions — consider polarizer', i: 'warning' },
  { id: 'distance', label: 'Distance to subject', status: 'pass', detail: '42 cm · in range', i: 'ruler' },
  { id: 'support', label: 'Stable surface', status: 'pass', detail: 'Turntable detected', i: 'cube' },
  { id: 'thermal', label: 'Device thermal', status: 'pass', detail: 'Nominal · 31 °C', i: 'thermal' },
  { id: 'storage', label: 'Storage available', status: 'pass', detail: '244 GB free · ~3.4 GB needed', i: 'download' },
];

const GUIDES = [
  { t: 'Move slowly', d: 'Keep angular velocity below 30 °/s. Walk a smooth orbit, not a stroll.', i: 'speed' },
  { t: 'Three passes', d: 'Eye-level, then high, then low — 360° each. Overlap by 60%.', i: 'refresh' },
  { t: 'Hands-free turntable', d: 'For objects under 30 cm, rotate the object — not the camera.', i: 'hand' },
  { t: 'Avoid shiny + clear', d: 'Glass, mirrors, water absorb poorly. Mark them or skip them.', i: 'warning' },
];

function StatusDot({ status, s = 28 }) {
  const c = status === 'pass' ? T.good : status === 'warn' ? T.warn : T.bad;
  const bg = status === 'pass' ? T.goodSoft : status === 'warn' ? T.warnSoft : T.badSoft;
  return (
    <div style={{ width: s, height: s, borderRadius: 99, display: 'grid', placeItems: 'center', background: bg, flexShrink: 0 }}>
      {status === 'pass' ? <Ic name="check" s={s * 0.5} c={c} sw={2.6} /> : <span style={{ color: c, fontSize: s * 0.5, fontWeight: 800, lineHeight: 1 }}>!</span>}
    </div>
  );
}

function CheckRow({ item }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 0' }}>
      <StatusDot status={item.status} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: T.ink, letterSpacing: -0.2 }}>{item.label}</div>
        <div className="st-num" style={{ fontSize: 11.5, color: T.text3, marginTop: 2 }}>{item.detail}</div>
      </div>
      <Ic name={item.i} s={16} c={T.text4} />
    </div>
  );
}

function GuideCard({ guide }) {
  return (
    <Card radius={16} style={{ padding: 14 }}>
      <div style={{ width: 32, height: 32, borderRadius: 10, background: T.accentSoft, display: 'grid', placeItems: 'center', marginBottom: 10 }}><Ic name={guide.i} s={17} c={T.accent} /></div>
      <div style={{ fontSize: 13.5, fontWeight: 700, letterSpacing: -0.2, color: T.ink }}>{guide.t}</div>
      <div style={{ fontSize: 11.5, color: T.text2, lineHeight: 1.4, marginTop: 4 }}>{guide.d}</div>
    </Card>
  );
}

function PhoneBriefing({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <StatusBar />
      <div className="st-scroll" style={{ position: 'absolute', inset: 0, top: 54, overflow: 'auto', padding: '8px 20px 110px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button className="st-tap" onClick={() => go('mode')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
          <Chip tone="neutral">Step 2 of 4</Chip>
          <button className="st-tap" onClick={() => go('library')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="close" s={16} c={T.text2} /></button>
        </div>
        <div style={{ marginTop: 18 }}>
          <Label>Scene briefing</Label>
          <div style={{ fontSize: 28, fontWeight: 720, letterSpacing: -0.9, color: T.ink, marginTop: 6, lineHeight: 1.05 }}>You're ready in 5 of 6</div>
        </div>
        <Card radius={20} style={{ padding: 16, marginTop: 14, display: 'flex', alignItems: 'center', gap: 16 }}>
          <Ring value={0.83} size={74} color={T.good} label="83" />
          <div>
            <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Scan-readiness: Excellent</div>
            <div style={{ fontSize: 12.5, color: T.text2, marginTop: 3, lineHeight: 1.35 }}>Resolve the reflection warning to reach 100.</div>
          </div>
        </Card>
        <Card radius={20} style={{ padding: '4px 16px', marginTop: 12 }}>
          {CHECKLIST.slice(0, 4).map((c, i) => (
            <React.Fragment key={c.id}><CheckRow item={c} />{i < 3 && <Rule />}</React.Fragment>
          ))}
        </Card>
        <div style={{ fontSize: 14, fontWeight: 700, letterSpacing: -0.2, color: T.ink, marginTop: 18, marginBottom: 10 }}>Pro tips for this scene</div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {GUIDES.slice(0, 2).map(g => <GuideCard key={g.t} guide={g} />)}
        </div>
      </div>
      <div style={{ position: 'absolute', bottom: 28, left: 20, right: 20 }}>
        <Button kind="accent" full size="lg" onClick={() => go('quality')}><Ic name="bolt" s={17} c={T.onAccent} /> Continue to Detail</Button>
      </div>
    </div>
  );
}

function PadBriefing({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <PadStatusBar />
      <div style={{ position: 'absolute', inset: 0, top: 30, display: 'flex', flexDirection: 'column', padding: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button className="st-tap" onClick={() => go('mode')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
            <div><Label>New Scan · Step 2 of 4</Label><div style={{ fontSize: 17, fontWeight: 700, letterSpacing: -0.3, color: T.ink, marginTop: 2 }}>Scene briefing & guidance</div></div>
          </div>
          <StepTabs active={1} />
          <Button kind="ghost" size="sm" onClick={() => go('quality')}>Skip briefing</Button>
        </div>
        <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '1.05fr .95fr', gap: 16, minHeight: 0, marginTop: 18 }}>
          {/* live preview */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14, minHeight: 0 }}>
            <div style={{ flex: 1, borderRadius: 22, overflow: 'hidden', position: 'relative', minHeight: 0, boxShadow: T.cardShadow }}>
              <Stage radius={22}><HeroModel w={580} h={400} /></Stage>
              <div style={{ position: 'absolute', top: 14, left: 14, display: 'flex', gap: 8 }}>
                <Chip tone="neutral" style={{ background: T.glassFill, backdropFilter: 'blur(14px)' }}><Ic name="camera" s={13} c={T.text2} /> Live preview</Chip>
                <Chip tone="accent"><span style={{ width: 6, height: 6, borderRadius: 99, background: T.accent, animation: 'st-pulse 1.4s infinite' }} /> AI watching</Chip>
              </div>
              <div style={{ position: 'absolute', bottom: 14, left: 14 }}>
                <Glass radius={14} style={{ padding: '10px 14px' }}>
                  <Label color={T.good}>Auto-detected</Label>
                  <div style={{ fontSize: 16, fontWeight: 700, letterSpacing: -0.3, color: T.ink, marginTop: 4 }}>Ceramic Vase · 14 cm</div>
                  <div className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text3, marginTop: 2 }}>conf 0.94 · 14.2 × 10.8 × 14.2 cm</div>
                </Glass>
              </div>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10 }}>
              {GUIDES.map(g => <GuideCard key={g.t} guide={g} />)}
            </div>
          </div>
          {/* readiness */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14, minHeight: 0 }}>
            <Card radius={22} style={{ padding: 20, display: 'flex', gap: 18, alignItems: 'center' }}>
              <Ring value={0.83} size={104} stroke={8} color={T.good} label="83" sub="SCAN READY" />
              <div style={{ flex: 1 }}>
                <Label color={T.good}>Readiness · excellent</Label>
                <div style={{ fontSize: 22, fontWeight: 720, letterSpacing: -0.6, color: T.ink, marginTop: 6 }}>5 of 6 checks pass</div>
                <div style={{ fontSize: 13, color: T.text2, marginTop: 6, lineHeight: 1.4 }}>Resolve the reflection warning to push fidelity to <b style={{ color: T.ink }}>4.2M tris</b> with confident PBR estimation.</div>
              </div>
            </Card>
            <Card radius={20} style={{ padding: '4px 18px', flex: 1, minHeight: 0, overflow: 'hidden' }}>
              {CHECKLIST.map((c, i) => (
                <React.Fragment key={c.id}><CheckRow item={c} />{i < CHECKLIST.length - 1 && <Rule />}</React.Fragment>
              ))}
            </Card>
            <div style={{ display: 'flex', gap: 10 }}>
              <Button kind="secondary" style={{ flex: 1 }}><Ic name="refresh" s={15} c={T.ink} /> Re-run analysis</Button>
              <Button kind="accent" style={{ flex: 2 }} onClick={() => go('quality')}><Ic name="bolt" s={17} c={T.onAccent} /> Continue to Detail</Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneBriefing, PadBriefing, CHECKLIST, GUIDES });
