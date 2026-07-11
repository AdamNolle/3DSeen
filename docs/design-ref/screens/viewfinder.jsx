// studio/screens/viewfinder.jsx — live capture scan (iPhone · iPad)
// Cleaned up + Liquid Glass: dark glass overlays float over the camera feed,
// telemetry is a single tidy capsule, nothing clips.

// dim studio camera feed with the subject
function CameraFeed({ children, vb = '0 0 402 874' }) {
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: '#0B0A09' }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(58% 70% at 50% 54%, #1f1914 0%, #0d0b09 60%, #060504 100%)' }} />
      <div style={{ position: 'absolute', top: 0, left: 0, width: '60%', height: '100%', background: 'radial-gradient(ellipse at 0% 30%, rgba(255,214,168,0.12), transparent 60%)', mixBlendMode: 'screen' }} />
      <svg width="100%" height="100%" viewBox={vb} preserveAspectRatio="xMidYMid slice" style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <radialGradient id="cf-b" cx="0.42" cy="0.34" r="0.66"><stop offset="0%" stopColor="#EBCFA9"/><stop offset="42%" stopColor="#9B7A5B"/><stop offset="100%" stopColor="#1c130c"/></radialGradient>
          <radialGradient id="cf-h" cx="0.34" cy="0.24" r="0.4"><stop offset="0%" stopColor="rgba(255,228,190,0.6)"/><stop offset="100%" stopColor="rgba(255,228,190,0)"/></radialGradient>
        </defs>
        <ellipse cx="201" cy="600" rx="120" ry="16" fill="rgba(0,0,0,0.65)"/>
        <rect x="135" y="560" width="132" height="44" rx="3" fill="#15110d"/>
        <path d="M142 560 C 150 480, 160 430, 168 392 C 176 366, 190 358, 201 358 C 212 358, 226 366, 234 392 C 242 430, 252 480, 260 560 Z" fill="url(#cf-b)"/>
        <ellipse cx="201" cy="300" rx="56" ry="72" fill="url(#cf-b)"/>
        <path d="M150 286 C 146 220, 178 188, 201 180 C 224 188, 256 220, 252 286 C 240 268, 224 252, 208 252 C 208 244, 202 240, 201 240 C 196 240, 192 244, 192 252 C 178 252, 162 268, 150 286 Z" fill="#241a12"/>
        <ellipse cx="184" cy="288" rx="38" ry="52" fill="url(#cf-h)"/>
      </svg>
      {children}
    </div>
  );
}

// AR bounding box (clean corner brackets + dimension caliper)
function ARBox({ vb, box, dim, accent }) {
  const a = accent || '#fff';
  const [x1, y1, x2, y2] = box;
  const k = 20;
  return (
    <svg width="100%" height="100%" viewBox={vb} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <rect x={x1} y={y1} width={x2 - x1} height={y2 - y1} rx="8" fill="none" stroke="rgba(255,255,255,0.20)" strokeWidth="1" />
      {[[x1, y1, 1, 1], [x2, y1, -1, 1], [x1, y2, 1, -1], [x2, y2, -1, -1]].map(([x, y, sx, sy], i) => (
        <path key={i} d={`M${x + sx * k} ${y} L${x + sx * 6} ${y} Q ${x} ${y} ${x} ${y + sy * 6} L${x} ${y + sy * k}`} stroke={a} strokeWidth="2.4" fill="none" strokeLinecap="round" />
      ))}
      <g stroke={a} strokeOpacity="0.55" strokeWidth="0.8" fill={a} fontSize="9" fontFamily={T.mono}>
        <line x1={x1 - 13} y1={y1} x2={x1 - 13} y2={y2} />
        <line x1={x1 - 16} y1={y1} x2={x1 - 10} y2={y1} /><line x1={x1 - 16} y1={y2} x2={x1 - 10} y2={y2} />
        <text x={x1 - 19} y={(y1 + y2) / 2 + 3} textAnchor="end" style={{ fontWeight: 600 }} strokeWidth="0">{dim}</text>
      </g>
    </svg>
  );
}

function Shutter({ size = 74, onClick }) {
  return (
    <button className="st-tap" onClick={onClick} style={{ width: size, height: size, borderRadius: 99, border: 'none', cursor: 'pointer', padding: 5, background: '#fff', boxShadow: 'inset 0 0 0 2.5px rgba(0,0,0,0.85), 0 4px 18px rgba(0,0,0,0.45)' }}>
      <div style={{ width: '100%', height: '100%', borderRadius: 9, background: T.bad }} />
    </button>
  );
}

// telemetry capsule: evenly-sized cells, hairline dividers, no clipping
function Telemetry({ items, style = {} }) {
  return (
    <Glass tone="dark" radius={15} style={{ display: 'flex', alignItems: 'stretch', padding: '9px 4px', ...style }}>
      {items.map(([k, v, c], i) => (
        <div key={k} style={{ flex: 1, minWidth: 0, padding: '0 8px', textAlign: 'center', borderLeft: i ? '0.5px solid rgba(255,255,255,0.12)' : 'none' }}>
          <div style={{ fontFamily: T.mono, fontSize: 8.5, fontWeight: 600, letterSpacing: 1, color: 'rgba(255,255,255,0.55)' }}>{k}</div>
          <div className="st-num" style={{ fontFamily: T.mono, fontSize: 13, fontWeight: 700, color: c || '#fff', marginTop: 3, lineHeight: 1 }}>{v}</div>
        </div>
      ))}
    </Glass>
  );
}

// small white-label used on dark glass
function DLabel({ children, color, style = {} }) {
  return <div style={{ fontFamily: T.mono, fontSize: 9.5, fontWeight: 600, letterSpacing: 1.3, textTransform: 'uppercase', color: color || 'rgba(255,255,255,0.55)', ...style }}>{children}</div>;
}

// ─── iPhone ─────────────────────────────────────────────────────────
function PhoneViewfinder({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <CameraFeed />
      <ARBox vb="0 0 402 874" box={[124, 250, 278, 548]} dim="14.2 cm" accent="#fff" />
      <StatusBar tone="light" />

      {/* top: back + REC capsule */}
      <div style={{ position: 'absolute', top: 58, left: 16, right: 16, display: 'flex', alignItems: 'center', gap: 8 }}>
        <Glass tone="dark" radius={13} onClick={() => go('briefing')} className="st-tap" style={{ width: 40, height: 40, display: 'grid', placeItems: 'center', cursor: 'pointer' }}><Ic name="close" s={16} c="#fff" /></Glass>
        <Glass tone="dark" radius={13} style={{ flex: 1, height: 40, display: 'flex', alignItems: 'center', gap: 9, padding: '0 13px' }}>
          <span style={{ width: 7, height: 7, borderRadius: 99, background: T.bad, animation: 'st-pulse 1.4s infinite' }} />
          <span style={{ fontFamily: T.mono, fontSize: 11, fontWeight: 700, color: '#fff', letterSpacing: 0.5 }}>REC</span>
          <span className="st-num" style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 600, color: '#fff' }}>00:42.3</span>
          <div style={{ flex: 1 }} />
          <span className="st-num" style={{ fontFamily: T.mono, fontSize: 10, color: 'rgba(255,255,255,0.6)' }}>OBJ · FULL · 4K</span>
        </Glass>
        <Glass tone="dark" radius={13} style={{ height: 40, display: 'flex', alignItems: 'center', gap: 5, padding: '0 12px' }}><Ic name="thermal" s={13} c="rgba(255,255,255,0.7)" /><span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: '#fff' }}>34°</span></Glass>
      </div>

      {/* telemetry capsule */}
      <div style={{ position: 'absolute', top: 106, left: 16, right: 16 }}>
        <Telemetry items={[['LUX', '1840'], ['DIST', '42cm'], ['SHARP', '0.94', '#7FD9A6'], ['MOTION', '34°/s', '#E7B24C']]} />
      </div>

      {/* compact coverage tile (top-right) */}
      <div style={{ position: 'absolute', top: 166, right: 16, width: 132 }}>
        <Glass tone="dark" radius={16} style={{ padding: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}><DLabel>Coverage</DLabel><span className="st-num" style={{ fontFamily: T.mono, fontSize: 9, color: 'rgba(255,255,255,0.4)' }}>22 SH</span></div>
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: 2 }}><CoverageSphere size={104} /></div>
          <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginTop: 2 }}>
            <div className="st-num" style={{ fontSize: 30, fontWeight: 720, letterSpacing: -1, color: '#fff', lineHeight: 1 }}>72<span style={{ fontSize: 13, color: 'rgba(255,255,255,0.5)', fontWeight: 600 }}>%</span></div>
            <div style={{ textAlign: 'right', fontSize: 9.5, fontWeight: 600, lineHeight: 1.45 }}>
              <div style={{ color: '#7FD9A6' }}>16 strong</div><div style={{ color: '#E7B24C' }}>3 weak</div><div style={{ color: '#FF8A7E' }}>3 gap</div>
            </div>
          </div>
        </Glass>
      </div>

      {/* object label under AR box */}
      <div style={{ position: 'absolute', top: 560, left: 16 }}>
        <Glass tone="dark" radius={13} style={{ padding: '9px 13px' }}>
          <DLabel color="#9FC0FF">AI Scene · Auto-Pilot</DLabel>
          <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: '#fff', marginTop: 3 }}>Ceramic bust</div>
          <div className="st-num" style={{ fontFamily: T.mono, fontSize: 10, color: 'rgba(255,255,255,0.55)', marginTop: 2 }}>14.2 × 10.8 × 14.2 cm · conf 0.94</div>
        </Glass>
      </div>

      {/* bottom dock */}
      <div style={{ position: 'absolute', bottom: 28, left: 16, right: 16, display: 'flex', flexDirection: 'column', gap: 9 }}>
        <div style={{ display: 'flex', justifyContent: 'center' }}>
          <Glass tone="dark" radius={99} style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '7px 14px' }}>
            <Ic name="speed" s={14} c="#E7B24C" /><span style={{ fontSize: 12.5, fontWeight: 650, color: '#fff' }}>Slow down · 34 → under 30°/s</span>
          </Glass>
        </div>
        <Glass tone="dark" radius={20} style={{ padding: '14px 16px', display: 'flex', alignItems: 'center' }}>
          <div style={{ width: 88 }}>
            <DLabel>Mode</DLabel>
            <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: -0.4, color: '#fff', marginTop: 2 }}>Object</div>
            <div className="st-num" style={{ fontFamily: T.mono, fontSize: 9.5, color: '#E7B24C', marginTop: 2 }}>FULL · 4K</div>
          </div>
          <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}><Shutter onClick={() => go('review')} /></div>
          <div style={{ width: 88, textAlign: 'right' }}>
            <DLabel style={{ textAlign: 'right' }}>ETA · Mac</DLabel>
            <div className="st-num" style={{ fontSize: 20, fontWeight: 720, letterSpacing: -0.8, color: '#fff', marginTop: 2 }}>1:52</div>
            <div className="st-num" style={{ fontFamily: T.mono, fontSize: 9.5, color: 'rgba(255,255,255,0.5)', marginTop: 2 }}>local 6:42</div>
          </div>
        </Glass>
      </div>
    </div>
  );
}

// ─── iPad ───────────────────────────────────────────────────────────
function PadViewfinder({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <CameraFeed vb="0 0 1194 834" />
      <ARBox vb="0 0 1194 834" box={[472, 222, 722, 648]} dim="18.4 cm" accent="#fff" />
      <PadStatusBar tone="light" left="9:41 · Object · 248 / 340 fr · 00:42.3" />

      {/* top bar */}
      <div style={{ position: 'absolute', top: 38, left: 20, right: 20, display: 'flex', alignItems: 'center', gap: 10, height: 46 }}>
        <Glass tone="dark" radius={14} onClick={() => go('briefing')} className="st-tap" style={{ width: 46, height: 46, display: 'grid', placeItems: 'center', cursor: 'pointer' }}><Ic name="close" s={17} c="#fff" /></Glass>
        <Glass tone="dark" radius={14} style={{ height: 46, display: 'flex', alignItems: 'center', gap: 12, padding: '0 18px' }}>
          <span style={{ width: 8, height: 8, borderRadius: 99, background: T.bad, animation: 'st-pulse 1.4s infinite' }} />
          <span style={{ fontFamily: T.mono, fontSize: 12, fontWeight: 700, color: '#fff', letterSpacing: 0.5 }}>REC</span>
          <span className="st-num" style={{ fontFamily: T.mono, fontSize: 13, fontWeight: 600, color: '#fff' }}>00:42.318</span>
          <span style={{ width: 0.5, height: 18, background: 'rgba(255,255,255,0.22)' }} />
          <span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: 'rgba(255,255,255,0.7)' }}>OBJECT · FULL · 4096²</span>
        </Glass>
        <div style={{ flex: 1 }} />
        <Glass tone="dark" radius={14} style={{ height: 46, display: 'flex', alignItems: 'stretch', padding: '0 4px' }}>
          {[['THERMAL', '34°C', 'thermal'], ['LIGHT', '1840 lx', 'light'], ['BATTERY', '78%', 'battery'], ['STORAGE', '244 GB', 'download']].map(([k, v, ic], i) => (
            <div key={k} style={{ display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '0 14px', borderLeft: i ? '0.5px solid rgba(255,255,255,0.12)' : 'none' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}><Ic name={ic} s={11} c="rgba(255,255,255,0.55)" /><span style={{ fontFamily: T.mono, fontSize: 8, color: 'rgba(255,255,255,0.5)', letterSpacing: 1 }}>{k}</span></div>
              <span className="st-num" style={{ fontFamily: T.mono, fontSize: 13, fontWeight: 600, color: '#fff', marginTop: 2 }}>{v}</span>
            </div>
          ))}
        </Glass>
      </div>

      {/* left rail */}
      <div style={{ position: 'absolute', top: 100, left: 20, bottom: 158, width: 252, display: 'flex', flexDirection: 'column', gap: 10 }}>
        <Glass tone="dark" radius={18} style={{ padding: 16 }}>
          <DLabel>Coverage</DLabel>
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: 4 }}><CoverageSphere size={184} /></div>
          <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
            <div className="st-num" style={{ fontSize: 44, fontWeight: 720, letterSpacing: -1.6, color: '#fff', lineHeight: 1 }}>72<span style={{ fontSize: 18, color: 'rgba(255,255,255,0.5)', fontWeight: 600 }}>%</span></div>
            <div style={{ textAlign: 'right', fontSize: 12, fontWeight: 600, lineHeight: 1.5 }}>
              <div style={{ color: '#7FD9A6' }}>16 strong</div><div style={{ color: '#E7B24C' }}>3 weak</div><div style={{ color: '#FF8A7E' }}>3 gap</div>
            </div>
          </div>
        </Glass>
        <Glass tone="dark" radius={18} style={{ padding: 16, flex: 1, minHeight: 0 }}>
          <DLabel>Surface guidance</DLabel>
          <div style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 11 }}>
            {[['Underside', 'tilt −25°', '#E7B24C'], ['Back-left', 'cw 15°', '#E7B24C'], ['Crown', 'lift camera', '#FF8A7E']].map(([l, d, c]) => (
              <div key={l} style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
                <span style={{ width: 7, height: 7, borderRadius: 99, background: c }} />
                <span style={{ flex: 1, fontSize: 13.5, color: 'rgba(255,255,255,0.85)' }}>{l}</span>
                <span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: c }}>{d}</span>
              </div>
            ))}
          </div>
        </Glass>
      </div>

      {/* right rail */}
      <div style={{ position: 'absolute', top: 100, right: 20, bottom: 158, width: 272, display: 'flex', flexDirection: 'column', gap: 10 }}>
        <Glass tone="dark" radius={18} style={{ padding: 16 }}>
          <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
            <div>
              <DLabel>Live frame · 0247</DLabel>
              <div className="st-num" style={{ fontSize: 26, fontWeight: 720, letterSpacing: -0.8, color: '#fff', marginTop: 6, display: 'flex', alignItems: 'baseline', gap: 3 }}>38.7<span style={{ fontSize: 12, color: 'rgba(255,255,255,0.5)', fontWeight: 600 }}>dB PSNR</span></div>
            </div>
            <Spark values={[33, 34, 32, 35, 36, 37, 38, 38.7, 38.5, 38.4, 38.7, 38.6]} w={104} h={34} color="#9FC0FF" />
          </div>
          <div style={{ height: 0.5, background: 'rgba(255,255,255,0.12)', margin: '14px 0' }} />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr', gap: 12 }}>
            {[['SHARP', '0.94'], ['PARALLAX', '8.4°'], ['DIST', '42cm'], ['FOCUS', '0.99']].map(([k, v]) => (
              <div key={k}><div style={{ fontFamily: T.mono, fontSize: 8.5, color: 'rgba(255,255,255,0.5)', letterSpacing: 0.6 }}>{k}</div><div className="st-num" style={{ fontFamily: T.mono, fontSize: 13.5, fontWeight: 600, color: '#fff', marginTop: 2 }}>{v}</div></div>
            ))}
          </div>
        </Glass>
        <Glass tone="dark" radius={18} style={{ padding: 16, flex: 1, minHeight: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}><DLabel>RGB · luma</DLabel><span className="st-num" style={{ fontFamily: T.mono, fontSize: 10, color: 'rgba(255,255,255,0.45)' }}>μ118 · σ42</span></div>
          <div style={{ marginTop: 12 }}><Histogram w={236} h={64} /></div>
          <div className="st-num" style={{ display: 'flex', justifyContent: 'space-between', fontFamily: T.mono, fontSize: 8.5, color: 'rgba(255,255,255,0.4)', marginTop: 6 }}><span>0</span><span>64</span><span>128</span><span>192</span><span>255</span></div>
        </Glass>
      </div>

      {/* bottom dock */}
      <div style={{ position: 'absolute', bottom: 20, left: 20, right: 20, display: 'flex', gap: 10, height: 126 }}>
        <Glass tone="dark" radius={18} style={{ padding: 16, width: 252 }}>
          <DLabel color="#9FC0FF">AI scene · Auto-Pilot</DLabel>
          <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: -0.5, color: '#fff', marginTop: 8 }}>Ceramic bust</div>
          <div className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: 'rgba(255,255,255,0.55)', marginTop: 6 }}>14.2 × 10.8 × 14.2 cm · conf 0.94</div>
        </Glass>
        <Glass tone="dark" radius={18} style={{ padding: 16, flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}><DLabel>Frame strip · recent</DLabel><span className="st-num" style={{ fontFamily: T.mono, fontSize: 10 }}><span style={{ color: '#7FD9A6' }}>kept 242</span> <span style={{ color: 'rgba(255,255,255,0.4)' }}>·</span> <span style={{ color: '#FF8A7E' }}>rej 6</span></span></div>
          <div style={{ marginTop: 12 }}><FrameStrip count={16} sel={13} h={48} /></div>
        </Glass>
        <Glass tone="dark" radius={18} style={{ padding: 16, width: 252, display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}><Shutter size={84} onClick={() => go('review')} /></div>
          <div style={{ textAlign: 'right' }}>
            <DLabel style={{ textAlign: 'right' }}>ETA · Mac</DLabel>
            <div className="st-num" style={{ fontSize: 26, fontWeight: 720, letterSpacing: -1, color: '#fff', marginTop: 2 }}>1:52</div>
            <div className="st-num" style={{ fontFamily: T.mono, fontSize: 10, color: 'rgba(255,255,255,0.5)' }}>local 6:42</div>
          </div>
        </Glass>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneViewfinder, PadViewfinder, CameraFeed, ARBox });
