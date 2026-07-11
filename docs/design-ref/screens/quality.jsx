// studio/screens/quality.jsx — detail / quality tier picker (5 tiers)

const TIERS = [
  { id: 'preview', name: 'Preview', tag: 'Real-time draft', tris: '120k', tex: '512', size: '12 MB', time: '8 s', use: 'Snap a quick reference', psnr: 22 },
  { id: 'reduced', name: 'Reduced', tag: 'Mobile-ready', tris: '480k', tex: '1024', size: '38 MB', time: '40 s', use: 'AR Quick Look, web preview', psnr: 28 },
  { id: 'medium', name: 'Medium', tag: 'Most projects', tris: '1.2M', tex: '2048', size: '92 MB', time: '2:15', use: 'Catalogs, light VFX, social', psnr: 33, recommended: true },
  { id: 'full', name: 'Full', tag: 'Studio fidelity', tris: '4.2M', tex: '4096', size: '184 MB', time: '6:42', use: 'Commercial, museum, PBR-correct', psnr: 38 },
  { id: 'raw', name: 'Raw', tag: 'Photogrammetric archive', tris: '16M+', tex: '8192', size: '1.1 GB', time: '21 min', use: 'Re-process later · color-managed EXR', psnr: 44 },
];

function TierPreview({ tier, size = 84 }) {
  const segs = { preview: 6, reduced: 10, medium: 14, full: 20, raw: 28 }[tier.id] || 12;
  return (
    <div style={{ width: size, height: size, borderRadius: 14, overflow: 'hidden', position: 'relative', flexShrink: 0, boxShadow: `inset 0 0 0 0.5px ${T.line}` }}>
      <Stage radius={14}>
        <svg width={size} height={size} viewBox="-50 -50 100 100" style={{ position: 'absolute', inset: 0 }}>
          {[...Array(segs)].map((_, i) => {
            const lat = (i / segs - 0.5) * Math.PI; const r = 32 * Math.cos(lat); const cy = 32 * Math.sin(lat) * 0.6;
            return <ellipse key={i} cx="0" cy={cy} rx={r} ry={r * 0.34} fill="none" stroke={STONE.lo} strokeOpacity={0.3 + (i/segs)*0.4} strokeWidth="0.5"/>;
          })}
          <circle r="13" fill={STONE.mid} opacity="0.9"/><circle cx="-4" cy="-4" r="7" fill={STONE.hi} opacity="0.8"/>
        </svg>
      </Stage>
    </div>
  );
}

function TierCard({ tier, selected, compact = false, onPick }) {
  return (
    <button className="st-tap" onClick={() => onPick && onPick(tier.id)} style={{
      position: 'relative', overflow: 'hidden', textAlign: 'left', cursor: 'pointer', width: '100%',
      borderRadius: compact ? 18 : 20, padding: compact ? 14 : 18,
      background: selected ? T.accentSoft : T.card, border: `0.5px solid ${selected ? T.accentLine : T.line}`,
      boxShadow: selected ? `0 0 0 1px ${T.accentLine}, ${T.cardShadow}` : T.cardShadow,
      display: 'flex', flexDirection: 'column', height: compact ? '100%' : 'auto',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14 }}>
        <TierPreview tier={tier} size={compact ? 60 : 84} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
            <div style={{ fontSize: compact ? 17 : 20, fontWeight: 720, letterSpacing: -0.4, color: T.ink }}>{tier.name}</div>
            {tier.recommended && <Chip tone="accent" style={{ fontSize: 9 }}>BEST</Chip>}
            {selected && !tier.recommended && <Chip tone="accent" style={{ fontSize: 9 }}>SELECTED</Chip>}
          </div>
          <Label color={selected ? T.accentText : T.text3} style={{ marginTop: 3 }}>{tier.tag}</Label>
          {!compact && <div style={{ fontSize: 13, color: T.text2, marginTop: 6, lineHeight: 1.35 }}>{tier.use}</div>}
        </div>
      </div>
      <div style={{ display: 'flex', marginTop: 14, paddingTop: 12, borderTop: `0.5px solid ${T.line}` }}>
        {[['Triangles', tier.tris], ['Textures', tier.tex + 'px'], ['Size', tier.size], ['Compute', tier.time]].map(([k, v], i) => (
          <div key={k} style={{ flex: 1, paddingLeft: i ? 10 : 0, borderLeft: i ? `0.5px solid ${T.line}` : 'none' }}>
            <Label>{k}</Label>
            <div className="st-num" style={{ fontSize: compact ? 13 : 15, fontWeight: 700, letterSpacing: -0.2, color: T.ink, marginTop: 3 }}>{v}</div>
          </div>
        ))}
      </div>
    </button>
  );
}

function PhoneQuality({ go }) {
  const [sel, setSel] = React.useState('medium');
  const tier = TIERS.find(t => t.id === sel);
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <StatusBar />
      <div className="st-scroll" style={{ position: 'absolute', inset: 0, top: 54, overflow: 'auto', padding: '8px 20px 110px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button className="st-tap" onClick={() => go('briefing')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
          <Chip tone="neutral">Step 3 of 4</Chip>
          <button className="st-tap" onClick={() => go('library')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="close" s={16} c={T.text2} /></button>
        </div>
        <div style={{ marginTop: 18 }}>
          <Label>Detail tier</Label>
          <div style={{ fontSize: 28, fontWeight: 720, letterSpacing: -0.9, color: T.ink, marginTop: 6 }}>How much detail?</div>
          <div style={{ fontSize: 13.5, color: T.text2, marginTop: 8 }}>Matches Apple's PhotogrammetrySession tiers. Re-process anytime.</div>
        </div>
        {/* scale */}
        <Card radius={18} style={{ padding: 16, marginTop: 14 }}>
          <div className="st-num" style={{ display: 'flex', justifyContent: 'space-between', fontFamily: T.mono, fontSize: 10, letterSpacing: 1, color: T.text3, marginBottom: 12 }}><span>FAST</span><span>BALANCED</span><span>ARCHIVE</span></div>
          <div style={{ height: 6, borderRadius: 99, background: `linear-gradient(90deg, ${T.text4}, ${T.accent})` }} />
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: -1 }}>
            {TIERS.map(t => {
              const on = t.id === sel;
              return (
                <button key={t.id} className="st-tap" onClick={() => setSel(t.id)} style={{ border: 'none', background: 'none', cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, padding: 0 }}>
                  <div style={{ width: 13, height: 13, borderRadius: 99, marginTop: -10, background: on ? T.accent : T.card, border: `2px solid ${on ? T.accent : T.lineStrong}`, boxShadow: on ? `0 0 0 3px ${T.accentSoft}` : 'none' }} />
                  <span style={{ fontFamily: T.mono, fontSize: 9.5, color: on ? T.ink : T.text3, fontWeight: on ? 700 : 500 }}>{t.name.toUpperCase()}</span>
                </button>
              );
            })}
          </div>
        </Card>
        <div style={{ marginTop: 14 }}><TierCard tier={tier} selected onPick={() => {}} /></div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 12 }}>
          {TIERS.filter(t => t.id !== sel).slice(0, 2).map(t => (
            <Card key={t.id} radius={14} onClick={() => setSel(t.id)} className="st-tap" style={{ padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer' }}>
              <TierPreview tier={t} size={40} />
              <div style={{ flex: 1 }}><div style={{ fontSize: 14, fontWeight: 650, color: T.ink }}>{t.name}</div><div className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text3, marginTop: 2 }}>{t.tris} tris · {t.size} · ~{t.time}</div></div>
              <Ic name="chev" s={15} c={T.text3} />
            </Card>
          ))}
        </div>
      </div>
      <div style={{ position: 'absolute', bottom: 28, left: 20, right: 20 }}>
        <Button kind="accent" full size="lg" onClick={() => go('viewfinder')}><Ic name="bolt" s={17} c={T.onAccent} /> Capture at {tier.name}</Button>
      </div>
    </div>
  );
}

function FidelityChart({ w = 480, h = 170, sel }) {
  return (
    <svg width="100%" height={h} viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" style={{ display: 'block' }}>
      <line x1="30" y1={h - 28} x2={w - 10} y2={h - 28} stroke={T.axis} />
      {[0,1,2,3].map(i => <line key={i} x1="30" y1={20 + i * (h - 70) / 3} x2={w - 10} y2={20 + i * (h - 70) / 3} stroke={T.grid} strokeDasharray="2 4" />)}
      {TIERS.map((t, i) => {
        const x = 55 + i * ((w - 80) / 4); const y = (h - 28) - ((t.psnr - 18) / 28) * (h - 56);
        const on = t.id === sel;
        return (
          <g key={t.id}>
            {i < 4 && (() => { const t2 = TIERS[i+1]; const x2 = 55 + (i+1)*((w-80)/4); const y2 = (h-28) - ((t2.psnr-18)/28)*(h-56); return <line x1={x} y1={y} x2={x2} y2={y2} stroke={T.accentLine} strokeWidth="1.5"/>; })()}
            <circle cx={x} cy={y} r={on ? 7 : 4.5} fill={on ? T.accent : T.card} stroke={T.accent} strokeWidth="1.6" />
            <text x={x} y={h - 12} fontSize="9" fill={T.text3} fontFamily={T.mono} textAnchor="middle">{t.name.toUpperCase()}</text>
            <text x={x} y={y - 11} fontSize="11" fill={T.ink} fontWeight="700" textAnchor="middle" className="st-num">{t.psnr}</text>
          </g>
        );
      })}
      <text x="34" y="16" fontSize="9" fill={T.text3} fontFamily={T.mono}>PSNR dB</text>
    </svg>
  );
}

function PadQuality({ go }) {
  const [sel, setSel] = React.useState('medium');
  const tier = TIERS.find(t => t.id === sel);
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <PadStatusBar />
      <div style={{ position: 'absolute', inset: 0, top: 30, display: 'flex', flexDirection: 'column', padding: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button className="st-tap" onClick={() => go('briefing')} style={{ width: 38, height: 38, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
            <div><Label>New Scan · Step 3 of 4</Label><div style={{ fontSize: 17, fontWeight: 700, letterSpacing: -0.3, color: T.ink, marginTop: 2 }}>Choose detail tier</div></div>
          </div>
          <StepTabs active={2} />
          <Button kind="accent" size="sm" onClick={() => go('viewfinder')}><Ic name="bolt" s={16} c={T.onAccent} /> Capture at {tier.name}</Button>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginTop: 18 }}>
          <Card radius={22} style={{ padding: 22 }}>
            <Label>Apple PhotogrammetrySession</Label>
            <div style={{ fontSize: 32, fontWeight: 720, letterSpacing: -1.1, color: T.ink, marginTop: 8, lineHeight: 1.02 }}>Five tiers,<br/>same source frames.</div>
            <div style={{ fontSize: 14, color: T.text2, marginTop: 12, lineHeight: 1.45 }}>3DSeen captures once at Raw and re-derives every lower tier on demand. You'll never need to re-scan.</div>
            <div style={{ display: 'flex', gap: 28, marginTop: 18 }}>
              {[['Captured frames','340',T.ink],['Raw archive','1.1 GB',T.ink],['Re-process','Unlimited',T.good]].map(([k,v,c]) => (
                <div key={k}><Label>{k}</Label><div className="st-num" style={{ fontSize: 22, fontWeight: 720, color: c, letterSpacing: -0.5, marginTop: 3 }}>{v}</div></div>
              ))}
            </div>
          </Card>
          <Card radius={22} style={{ padding: 22 }}>
            <Label color={T.accentText}>Fidelity comparison</Label>
            <div style={{ marginTop: 14 }}><FidelityChart sel={sel} /></div>
          </Card>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 12, flex: 1, minHeight: 0, marginTop: 16 }}>
          {TIERS.map(t => <TierCard key={t.id} tier={t} selected={t.id === sel} compact onPick={setSel} />)}
        </div>
        <Card radius={14} style={{ padding: '10px 16px', marginTop: 16, display: 'flex', alignItems: 'center', gap: 10 }}>
          <Ic name="info" s={16} c={T.accent} />
          <span style={{ fontSize: 12.5, color: T.text2 }}>For commercial fidelity, capture at <b style={{ color: T.ink }}>Raw</b> and view/share at <b style={{ color: T.ink }}>Full</b>. Re-derive in the library anytime — your iPhone keeps the archive, your Mac does the heavy lifting.</span>
        </Card>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneQuality, PadQuality, TIERS });
