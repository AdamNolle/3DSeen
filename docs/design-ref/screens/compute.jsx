// studio/screens/compute.jsx — compute pipeline & Mac handoff (iPhone · iPad · Mac)
// The hero handoff: capture on device, render on the Mac's Neural Engine.

// Clean particle-beam arc (cobalt accent, no neon glow)
function HandoffArc({ progress = 0.58, width = 360, height = 70, dots = 26 }) {
  const lift = height * 0.5;
  const path = `M 10 ${height / 2} Q ${width / 2} ${height / 2 - lift} ${width - 10} ${height / 2}`;
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} style={{ display: 'block', overflow: 'visible' }}>
      <path d={path} fill="none" stroke={T.line} strokeWidth="1.4" strokeDasharray="2 6" strokeLinecap="round" />
      {[...Array(dots)].map((_, i) => {
        const t = i / (dots - 1);
        const mx = width / 2, my = height / 2 - lift;
        const x = (1 - t) * (1 - t) * 10 + 2 * (1 - t) * t * mx + t * t * (width - 10);
        const y = (1 - t) * (1 - t) * (height / 2) + 2 * (1 - t) * t * my + t * t * (height / 2);
        const active = t <= progress;
        return <circle key={i} cx={x} cy={y} r={active ? 2.6 : 1.6} fill={active ? T.accent : T.text3} opacity={active ? 1 : 0.5} />;
      })}
    </svg>
  );
}

const COMPUTE_OPTIONS = {
  mac: { id: 'mac', name: 'Mac handoff', icon: 'laptop', tag: 'M-series Neural Engine · no thermal cap', best: true,
    stats: [['ETA', '1:52', () => T.accentText], ['Speed', '3.6×', null], ['Battery', '0%', () => T.good], ['Quality', 'Full', () => T.good]] },
  local: { id: 'local', name: 'On-device', icon: 'chip', tag: 'RealityKit · auto-throttle · offline-ready',
    stats: [['ETA', '6:42', null], ['Speed', '1.0×', null], ['Battery', '~22%', () => T.warn], ['Throttle', 'Auto', () => T.good]] },
};

function OptionCard({ opt, selected, onPick, big = false }) {
  return (
    <button className="st-tap" onClick={() => onPick(opt.id)} style={{
      textAlign: 'left', cursor: 'pointer', width: '100%', borderRadius: big ? 20 : 18, padding: big ? 18 : 15,
      background: selected ? T.accentSoft : T.card, border: `0.5px solid ${selected ? T.accentLine : T.line}`,
      boxShadow: selected ? `0 0 0 1px ${T.accentLine}, ${T.cardShadow}` : T.cardShadow,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
        <div style={{ width: 38, height: 38, borderRadius: 11, background: selected ? T.accent : T.fieldFill, display: 'grid', placeItems: 'center', boxShadow: selected ? 'none' : `inset 0 0 0 0.5px ${T.line}` }}>
          <Ic name={opt.icon} s={20} c={selected ? T.onAccent : T.text2} />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
            <span style={{ fontSize: 16, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>{opt.name}</span>
            {opt.best && <Chip tone="accent" style={{ fontSize: 9 }}>FASTEST</Chip>}
          </div>
          <Label color={selected ? T.accentText : T.text3} style={{ marginTop: 3 }}>{opt.tag}</Label>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
        {opt.stats.map(([k, v, c]) => <div key={k} style={{ flex: 1 }}><Stat k={k} v={v} c={c ? c() : undefined} size="sm" /></div>)}
      </div>
    </button>
  );
}

// little device glyphs
function PhoneGlyph({ w = 46, label, sub }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{ width: w, height: w * 1.6, borderRadius: 10, margin: '0 auto', background: T.ink, padding: 3, boxShadow: T.cardShadowLg }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 8, overflow: 'hidden', position: 'relative' }}><Stage radius={8}><HeroModel w={w} h={w * 1.6} /></Stage></div>
      </div>
      <div style={{ fontSize: 12.5, fontWeight: 650, color: T.ink, marginTop: 8 }}>{label}</div>
      <Label color={T.accentText} style={{ marginTop: 2 }}>{sub}</Label>
    </div>
  );
}
function MacGlyph({ w = 92, label, sub }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{ width: w, height: w * 0.64, borderRadius: 7, margin: '0 auto', background: T.ink, padding: 3, boxShadow: T.cardShadowLg }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 4, overflow: 'hidden', position: 'relative' }}><Stage radius={4}><HeroModel w={w} h={w * 0.64} /></Stage></div>
      </div>
      <div style={{ width: w * 1.18, height: 4, background: T.lineStrong, margin: '3px auto 0', borderRadius: '0 0 3px 3px' }} />
      <div style={{ fontSize: 12.5, fontWeight: 650, color: T.ink, marginTop: 7 }}>{label}</div>
      <Label style={{ marginTop: 2, color: T.text3 }}>{sub}</Label>
    </div>
  );
}

// ─── iPhone ─────────────────────────────────────────────────────────
function PhoneCompute({ go }) {
  const [sel, setSel] = React.useState('mac');
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <StatusBar />
      <div className="st-scroll" style={{ position: 'absolute', inset: 0, top: 54, overflow: 'auto', padding: '8px 20px 110px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button className="st-tap" onClick={() => go('review')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
          <Chip tone="neutral">Step 4 of 4</Chip>
          <button className="st-tap" onClick={() => go('library')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="close" s={16} c={T.text2} /></button>
        </div>
        <div style={{ marginTop: 18 }}>
          <Label>Where should we render?</Label>
          <div style={{ fontSize: 28, fontWeight: 720, letterSpacing: -0.9, color: T.ink, marginTop: 6 }}>Compute pipeline</div>
          <div style={{ fontSize: 13.5, color: T.text2, marginTop: 8 }}>Stay on iPhone, or hand off to your Mac on Wi-Fi.</div>
        </div>
        <Card radius={22} style={{ padding: 20, marginTop: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <PhoneGlyph label="iPhone 16 Pro" sub="SCAN · 1.1 GB" />
            <div style={{ flex: 1, padding: '0 6px' }}>
              <HandoffArc width={150} height={54} progress={0.62} />
              <div className="st-num" style={{ textAlign: 'center', fontFamily: T.mono, fontSize: 9.5, color: T.accentText, letterSpacing: 1, marginTop: 2 }}>MULTIPEER · 1.2 Gbps</div>
            </div>
            <MacGlyph w={84} label="MacBook Pro" sub="M4 MAX" />
          </div>
        </Card>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 12 }}>
          <OptionCard opt={COMPUTE_OPTIONS.mac} selected={sel === 'mac'} onPick={setSel} />
          <OptionCard opt={COMPUTE_OPTIONS.local} selected={sel === 'local'} onPick={setSel} />
        </div>
      </div>
      <div style={{ position: 'absolute', bottom: 28, left: 20, right: 20 }}>
        <Button kind="accent" full size="lg" onClick={() => go(sel === 'mac' ? 'viewer' : 'viewer')}>
          <Ic name={sel === 'mac' ? 'laptop' : 'chip'} s={17} c={T.onAccent} /> {sel === 'mac' ? 'Hand off to MacBook Pro' : 'Compute on iPhone'}
        </Button>
      </div>
    </div>
  );
}

// ─── iPad ───────────────────────────────────────────────────────────
function PadCompute({ go }) {
  const [sel, setSel] = React.useState('mac');
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <PadStatusBar />
      <div style={{ position: 'absolute', inset: 0, top: 30, display: 'flex', flexDirection: 'column', padding: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button className="st-tap" onClick={() => go('review')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
            <div><Label>Step 4 of 4 · Compute pipeline</Label><div style={{ fontSize: 17, fontWeight: 700, letterSpacing: -0.3, color: T.ink, marginTop: 2 }}>Where should we render?</div></div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <Button kind="secondary" size="sm" onClick={() => go('viewer')}><Ic name="chip" s={15} c={T.ink} /> Compute on iPad</Button>
            <Button kind="accent" size="sm" onClick={() => go('viewer')}><Ic name="laptop" s={15} c={T.onAccent} /> Hand off to Mac</Button>
          </div>
        </div>
        <Card radius={26} style={{ flex: 1, padding: 28, marginTop: 18, display: 'flex', flexDirection: 'column', minHeight: 0, position: 'relative', overflow: 'hidden' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <Label color={T.accentText}>Hub &amp; spoke</Label>
              <div style={{ fontSize: 42, fontWeight: 730, letterSpacing: -1.6, color: T.ink, marginTop: 8, lineHeight: 1 }}>Capture here.<br /><span style={{ color: T.accentText }}>Render there.</span></div>
              <div style={{ fontSize: 14, color: T.text2, marginTop: 12, maxWidth: 430, lineHeight: 1.45 }}>MultipeerConnectivity streams the raw scan to your Mac so the M-series Neural Engine renders without thermal limits — while your iPad stays cool.</div>
            </div>
            <Card inset radius={16} style={{ padding: 16, width: 280 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ width: 9, height: 9, borderRadius: 99, background: T.good }} />
                <span style={{ fontSize: 13, fontWeight: 700, letterSpacing: -0.2, color: T.ink }}>Connected to “Adam's MBP”</span>
              </div>
              <div className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text3, marginTop: 4 }}>peer · 192.168.1.42 · 1.2 Gbps</div>
              <div style={{ display: 'flex', gap: 18, marginTop: 14 }}>
                <Stat k="Ping" v="4" unit="ms" size="sm" /><Stat k="Loss" v="0" unit="%" size="sm" /><Stat k="Sent" v="1.1" unit="GB" c={T.accentText} size="sm" />
              </div>
            </Card>
          </div>
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'space-around', padding: '10px 50px', minHeight: 0, position: 'relative' }}>
            <div style={{ textAlign: 'center' }}>
              <div style={{ width: 180, height: 128, borderRadius: 16, background: T.ink, padding: 6, boxShadow: T.cardShadowLg }}>
                <div style={{ width: '100%', height: '100%', borderRadius: 10, overflow: 'hidden', position: 'relative' }}><Stage radius={10}><HeroModel w={180} h={128} /></Stage></div>
              </div>
              <div style={{ fontSize: 14, fontWeight: 700, color: T.ink, marginTop: 10 }}>iPad Pro M4</div>
              <Label color={T.accentText} style={{ marginTop: 2 }}>SCAN COMPLETE · 1.1 GB</Label>
            </div>
            <div style={{ flex: 1, padding: '0 20px', position: 'relative', maxWidth: 460 }}>
              <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 8 }}>
                <Glass radius={999} style={{ padding: '6px 14px', display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                  <Ic name="bolt" s={13} c={T.accent} /><span className="st-num" style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 700, color: T.ink }}>STREAMING · 58%</span><span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3 }}>652 / 1124 MB</span>
                </Glass>
              </div>
              <HandoffArc width={420} height={90} progress={0.58} />
              <div style={{ display: 'flex', justifyContent: 'center', gap: 8, marginTop: 8 }}>
                {['AES-256', 'multipeer', 'ETA 0:38'].map(t => <Chip key={t} tone="neutral" style={{ fontFamily: T.mono, fontSize: 10.5 }}>{t}</Chip>)}
              </div>
            </div>
            <div style={{ textAlign: 'center' }}>
              <div style={{ width: 200, height: 128, borderRadius: 9, background: T.ink, padding: 5, boxShadow: T.cardShadowLg }}>
                <div style={{ width: '100%', height: '100%', borderRadius: 5, overflow: 'hidden', position: 'relative' }}><Stage radius={5}><HeroModel w={200} h={128} material="wire" /></Stage></div>
              </div>
              <div style={{ width: 64, height: 5, background: T.lineStrong, margin: '4px auto 0', borderRadius: '0 0 3px 3px' }} />
              <div style={{ fontSize: 14, fontWeight: 700, color: T.ink, marginTop: 9 }}>MacBook Pro M4 Max</div>
              <Label color={T.accentText} style={{ marginTop: 2 }}>RECEIVING · NEURAL ENGINE</Label>
            </div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
            <OptionCard opt={COMPUTE_OPTIONS.local} selected={sel === 'local'} onPick={setSel} big />
            <OptionCard opt={COMPUTE_OPTIONS.mac} selected={sel === 'mac'} onPick={setSel} big />
          </div>
        </Card>
      </div>
    </div>
  );
}

// ─── Mac (compute dashboard — receiving + processing) ───────────────
const PIPELINE = [
  { id: 'ingest', l: 'Frame ingest', sub: '334 frames · aligned', pct: 1, done: true },
  { id: 'sparse', l: 'Sparse cloud', sub: '1.2M points · SfM', pct: 1, done: true },
  { id: 'dense', l: 'Dense reconstruction', sub: 'MVS · depth fusion', pct: 0.74, active: true },
  { id: 'mesh', l: 'Meshing', sub: 'Poisson · 4.2M tris', pct: 0 },
  { id: 'texture', l: 'Texturing', sub: '8K PBR · albedo/normal', pct: 0 },
  { id: 'optimize', l: 'Optimize &amp; export tiers', sub: 'decimate · UV · USDZ', pct: 0 },
];

function MacCompute({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, display: 'flex', flexDirection: 'column' }}>
      <div style={{ height: 52, flexShrink: 0, borderBottom: `0.5px solid ${T.line}`, display: 'flex', alignItems: 'center', gap: 14, padding: '0 18px 0 84px', background: T.card2 }}>
        <button className="st-tap" onClick={() => go('library')} style={{ height: 30, padding: '0 10px', borderRadius: 8, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 600, color: T.text2 }}><Ic name="back" s={15} c={T.text2} /> Library</button>
        <Rule vertical style={{ height: 22 }} />
        <span style={{ width: 8, height: 8, borderRadius: 99, background: T.accent, boxShadow: `0 0 0 3px ${T.accentSoft}` }} />
        <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Compute · Celestial Bust</div>
        <Chip tone="accent"><Ic name="laptop" s={13} c={T.accentText} /> Handoff from iPhone</Chip>
        <div style={{ flex: 1 }} />
        <Chip tone="neutral"><Ic name="clock" s={13} c={T.text2} /> ETA 1:52</Chip>
      </div>
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {/* pipeline rail */}
        <div style={{ width: 320, flexShrink: 0, borderRight: `0.5px solid ${T.line}`, background: T.card2, padding: 22, display: 'flex', flexDirection: 'column' }}>
          <Label>Pipeline · RealityKit on M4 Max</Label>
          <div style={{ marginTop: 16, flex: 1 }}>
            {PIPELINE.map((s, i) => {
              const c = s.done ? T.good : s.active ? T.accent : T.text4;
              return (
                <div key={s.id} style={{ display: 'flex', gap: 12, paddingBottom: i < PIPELINE.length - 1 ? 18 : 0 }}>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                    <div style={{ width: 26, height: 26, borderRadius: 99, flexShrink: 0, display: 'grid', placeItems: 'center', background: s.done ? T.good : s.active ? T.accentSoft : T.fieldFill, boxShadow: s.active ? `0 0 0 3px ${T.accentSoft}` : 'none' }}>
                      {s.done ? <Ic name="check" s={14} c="#fff" sw={2.6} /> : s.active ? <span style={{ width: 8, height: 8, borderRadius: 99, background: T.accent }} /> : <span className="st-num" style={{ fontSize: 11, fontWeight: 700, color: T.text3 }}>{i + 1}</span>}
                    </div>
                    {i < PIPELINE.length - 1 && <div style={{ width: 2, flex: 1, marginTop: 6, minHeight: 18, background: s.done ? T.good : T.line, borderRadius: 2 }} />}
                  </div>
                  <div style={{ flex: 1, paddingTop: 2 }}>
                    <div style={{ fontSize: 14, fontWeight: 650, color: s.active || s.done ? T.ink : T.text2 }} dangerouslySetInnerHTML={{ __html: s.l }} />
                    <div className="st-num" style={{ fontSize: 11, color: T.text3, marginTop: 2 }} dangerouslySetInnerHTML={{ __html: s.sub }} />
                    {s.active && <div style={{ marginTop: 8 }}><Meter value={s.pct} color={T.accent} height={5} /></div>}
                  </div>
                </div>
              );
            })}
          </div>
          <Card inset radius={14} style={{ padding: 14 }}>
            <Label color={T.accentText}>Live throughput</Label>
            <div style={{ display: 'flex', gap: 16, marginTop: 10 }}>
              <Stat k="Frames/s" v="184" size="sm" /><Stat k="Elapsed" v="2:38" size="sm" /><Stat k="Remaining" v="1:52" c={T.accentText} size="sm" />
            </div>
          </Card>
        </div>
        {/* live preview */}
        <div style={{ flex: 1, position: 'relative', minWidth: 0, borderRight: `0.5px solid ${T.line}` }}>
          <Stage><HeroModel w={620} h={620} material="wire" /></Stage>
          <div style={{ position: 'absolute', top: 18, left: 18 }}><Chip tone="accent"><span style={{ width: 6, height: 6, borderRadius: 99, background: T.accent, animation: 'st-pulse 1.4s infinite' }} /> Dense reconstruction · 74%</Chip></div>
          <div style={{ position: 'absolute', bottom: 18, left: '50%', transform: 'translateX(-50%)' }}>
            <Glass radius={16} style={{ padding: '12px 18px', display: 'flex', gap: 26 }}>
              <Stat k="Points" v="3.1M" size="sm" /><Stat k="Depth maps" v="334" size="sm" /><Stat k="Confidence" v="0.96" c={T.good} size="sm" /><Stat k="Tris (est)" v="4.2M" size="sm" />
            </Glass>
          </div>
        </div>
        {/* telemetry panel */}
        <div className="st-scroll" style={{ width: 300, flexShrink: 0, background: T.card2, overflow: 'auto', padding: 22, display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div>
            <Label>Hardware</Label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14, marginTop: 14 }}>
              {[['Neural Engine', 0.92, T.accent, '38 TOPS'], ['GPU · 40-core', 0.78, T.accent, '76%'], ['CPU · 16-core', 0.34, T.text2, '34%'], ['Unified memory', 0.46, T.text2, '22 / 48 GB']].map(([l, v, c, r]) => (
                <div key={l}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                    <span style={{ fontSize: 12.5, fontWeight: 600, color: T.ink }}>{l}</span>
                    <span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text2 }}>{r}</span>
                  </div>
                  <Meter value={v} color={c} height={5} />
                </div>
              ))}
            </div>
          </div>
          <Rule />
          <div>
            <Label color={T.good}>Thermals</Label>
            <div style={{ display: 'flex', gap: 16, marginTop: 12 }}>
              <Stat k="SoC" v="58" unit="°C" c={T.good} size="sm" /><Stat k="Fans" v="2400" unit="rpm" size="sm" /><Stat k="Power" v="46" unit="W" size="sm" />
            </div>
          </div>
          <Rule />
          <div>
            <Label>Transfer log</Label>
            <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 7 }}>
              {[['14:02:11', 'Received 334 frames', T.good], ['14:02:14', 'Sparse cloud built', T.good], ['14:04:49', 'Dense MVS running…', T.accentText], ['—', 'Meshing queued', T.text3]].map(([t, m, c], i) => (
                <div key={i} style={{ display: 'flex', gap: 10 }}>
                  <span className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text4, width: 56, flexShrink: 0 }}>{t}</span>
                  <span style={{ fontSize: 12, color: c, fontWeight: 500 }}>{m}</span>
                </div>
              ))}
            </div>
          </div>
          <div style={{ flex: 1 }} />
          <Button kind="accent" full onClick={() => go('viewer')}><Ic name="cube" s={16} c={T.onAccent} /> Open when ready</Button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneCompute, PadCompute, MacCompute });
