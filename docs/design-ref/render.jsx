// studio/render.jsx — premium rendered content: 3D model, coverage maps, thumbnails, charts.
// Everything sits on a neutral studio stage with warm-stone materials. No neon, no glow.

// ── Hero 3D model: classical bust, warm stone, soft accent rim ──────
function HeroModel({ w = 600, h = 600, material = 'pbr', accent }) {
  const a = accent || T.accent;
  const wire = material === 'wire';
  const metal = material === 'metal';
  const matte = material === 'matte';
  const baseHi = metal ? '#F1EEE9' : STONE.hi;
  const baseMid = metal ? '#9A9DA2' : STONE.mid;
  const baseLo = metal ? '#3B3E42' : STONE.lo;
  return (
    <svg width={w} height={h} viewBox="0 0 600 600" preserveAspectRatio="xMidYMid meet" style={{ display: 'block' }}>
      <defs>
        <radialGradient id="hm-body" cx="0.4" cy="0.32" r="0.78">
          <stop offset="0%" stopColor={baseHi}/>
          <stop offset="48%" stopColor={baseMid}/>
          <stop offset="100%" stopColor={baseLo}/>
        </radialGradient>
        <radialGradient id="hm-hi" cx="0.32" cy="0.24" r="0.5">
          <stop offset="0%" stopColor="rgba(255,255,255,0.85)"/>
          <stop offset="100%" stopColor="rgba(255,255,255,0)"/>
        </radialGradient>
        <radialGradient id="hm-rim" cx="0.82" cy="0.6" r="0.45">
          <stop offset="0%" stopColor={a} stopOpacity={matte ? 0.18 : 0.42}/>
          <stop offset="100%" stopColor={a} stopOpacity="0"/>
        </radialGradient>
        <linearGradient id="hm-plinth" x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor={T.mode === 'dark' ? '#33333A' : '#D8D5CD'}/>
          <stop offset="100%" stopColor={T.mode === 'dark' ? '#1A1A1E' : '#B7B3A8'}/>
        </linearGradient>
      </defs>
      {/* contact shadow */}
      <ellipse cx="300" cy="545" rx="150" ry="22" fill="rgba(20,18,14,0.18)"/>
      <ellipse cx="300" cy="540" rx="100" ry="12" fill="rgba(20,18,14,0.16)"/>
      {/* plinth */}
      <rect x="206" y="512" width="188" height="40" rx="4" fill="url(#hm-plinth)"/>
      <rect x="206" y="512" width="188" height="5" rx="2" fill="#fff" opacity={T.mode === 'dark' ? 0.10 : 0.45}/>
      {wire ? (
        <g fill="none" stroke={a} strokeWidth="0.7" opacity="0.8">
          <path d="M212 512 C 222 432, 232 372, 242 322 C 252 292, 272 282, 300 282 C 328 282, 348 292, 358 322 C 368 372, 378 432, 388 512"/>
          {[...Array(8)].map((_, i) => <ellipse key={i} cx="300" cy={512 - i * 28} rx={92 - i * 6} ry={5 + i}/>)}
          <ellipse cx="300" cy="270" rx="34" ry="6"/>
          <ellipse cx="300" cy="182" rx="78" ry="100"/>
          {[...Array(9)].map((_, i) => <ellipse key={i} cx="300" cy="182" rx={78 - i*8} ry="100"/>)}
          {[...Array(11)].map((_, i) => {
            const x = 300 + (i - 5) * 15;
            return <line key={i} x1={x} y1="84" x2={x} y2="280"/>;
          })}
        </g>
      ) : (
        <g>
          <path d="M212 512 C 222 432, 232 372, 242 322 C 252 292, 272 282, 300 282 C 328 282, 348 292, 358 322 C 368 432, 378 432, 388 512 Z" fill="url(#hm-body)"/>
          <path d="M272 292 C 272 252, 272 222, 287 202 L 313 202 C 328 222, 328 252, 328 292" fill="url(#hm-body)"/>
          <ellipse cx="300" cy="182" rx="78" ry="100" fill="url(#hm-body)"/>
          <path d="M227 162 C 222 82, 262 42, 300 32 C 338 42, 378 82, 373 162 C 358 142, 338 122, 318 122 C 318 112, 308 107, 300 107 C 292 107, 282 112, 282 122 C 262 122, 242 142, 227 162 Z" fill={metal ? '#52565B' : STONE.deep}/>
          <ellipse cx="282" cy="162" rx="54" ry="74" fill="url(#hm-hi)"/>
          <ellipse cx="322" cy="280" rx="80" ry="220" fill="url(#hm-rim)"/>
        </g>
      )}
      {matte && <rect x="0" y="0" width="600" height="600" fill={T.mode === 'dark' ? '#000' : '#fff'} opacity="0.07"/>}
    </svg>
  );
}

// ── Coverage dome: clean shells, status-colored, no glow ────────────
function CoverageDome({ size = 320, showDrops = true, drops = [] }) {
  const good = T.good, warn = T.warn, bad = T.bad;
  return (
    <svg width={size} height={size * 0.92} viewBox="-110 -98 220 196" style={{ display: 'block' }}>
      <defs>
        <radialGradient id="cd-core" cx="0.4" cy="0.38">
          <stop offset="0%" stopColor={STONE.hi}/>
          <stop offset="55%" stopColor={STONE.mid}/>
          <stop offset="100%" stopColor={STONE.deep}/>
        </radialGradient>
      </defs>
      <ellipse cx="0" cy="80" rx="78" ry="6" fill="rgba(20,18,14,0.14)"/>
      {[78, 63, 48].map((r, ri) => (
        {/* [decorative SVG span: concentric coverage shells] */}
      ))}
      {/* [decorative SVG span: core dome fill / latitude lines] */}
      {/* [decorative SVG span: coverage wedge overlay] */}
      {showDrops && drops.map((d, i) => {
        const x = (d.x - 50) / 50 * 76; const y = (d.y - 50) / 50 * 34;
        const c = d.severity === 'high' ? bad : d.severity === 'med' ? warn : T.accent;
        return (
          {/* [decorative SVG span: drop marker dot for d at (x,y) colored by severity] */}
        );
      })}
    </svg>
  );
}

// ── Coverage sphere (viewfinder, compact, clean) ────────────────────
function CoverageSphere({ size = 180, pct = 72 }) {
  const wedges = 22;
  const covered = [0,1,2,3,4,5,7,8,9,10,11,13,15,16,17,18];
  const partial = [6, 12, 19];
  return (
    <svg width={size} height={size} viewBox="-105 -105 210 210" style={{ display: 'block' }}>
      {/* [decorative SVG span: sphere base] */}
      {[-60,-30,0,30,60].map((lat, li) => (
        {/* [decorative SVG span: latitude ring] */}
      ))}
      {[...Array(wedges)].map((_, i) => {
        const a1 = (i / wedges) * Math.PI * 2;
        const a2 = ((i + 1) / wedges) * Math.PI * 2;
        const r1 = 66, r2 = 92;
        const pp = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * 0.34];
        const [x1,y1] = pp(a1,r1), [x2,y2] = pp(a2,r1), [x3,y3] = pp(a2,r2), [x4,y4] = pp(a1,r2);
        const c = covered.includes(i) ? T.good : partial.includes(i) ? T.warn : T.bad;
        const op = covered.includes(i) ? 0.42 : 0.6;
        return {/* [decorative SVG span: coverage wedge polygon] */};
      })}
      {/* [decorative SVG span: center pct label] */}
    </svg>
  );
}

// ── Scan thumbnail (library) — clean studio render ──────────────────
const SCAN_TONES = {
  bone:     ['#EFE7D7', '#9B8769'],
  rust:     ['#D8AE7E', '#7A4F2E'],
  walnut:   ['#C0A079', '#5E4129'],
  graphite: ['#D2D4D8', '#5A5E66'],
  slate:    ['#AEB9BD', '#4C5A60'],
  ice:      ['#CFE0E2', '#566C70'],
};
function ScanThumb({ scan, radius = 14, style = {}, label = true }) {
  const [hi, lo] = SCAN_TONES[scan.tone] || SCAN_TONES.bone;
  return (
    <div className="st-tap" style={{
      position: 'relative', borderRadius: radius, overflow: 'hidden', aspectRatio: '1 / 1.16',
      background: T.mode === 'dark'
        ? `radial-gradient(115% 90% at 50% 0%, #2b2b31, #161618)`
        : `radial-gradient(115% 90% at 50% 0%, #FAFAF8, #E7E5DF)`,
      border: `0.5px solid ${T.line}`, boxShadow: T.cardShadow, ...style,
    }}>
      <svg width="100%" height="100%" viewBox="0 0 100 116" preserveAspectRatio="xMidYMid slice" style={{ position: 'absolute', inset: 0 }}>
        {/* [decorative SVG span: thumbnail gradient defs] */}
        {/* [decorative SVG span: object silhouette hi/lo] */}
        {/* [decorative SVG span: rim highlight] */}
        {/* [decorative SVG span: floor shadow] */}
      </svg>
      {label && (
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '22px 11px 10px',
          background: T.mode === 'dark' ? 'linear-gradient(to top, rgba(0,0,0,0.7), transparent)' : 'linear-gradient(to top, rgba(255,255,255,0.85), transparent)' }}>
          <div style={{ fontSize: 13, fontWeight: 650, color: T.ink, letterSpacing: -0.3, lineHeight: 1.1 }}>{scan.name}</div>
          <div className="st-num" style={{ fontFamily: T.mono, fontSize: 9.5, color: T.text3, marginTop: 3, letterSpacing: 0.3 }}>{scan.mode} · {scan.tier} · {scan.mb} MB</div>
        </div>
      )}
      <div style={{ position: 'absolute', top: 9, left: 9 }}>
        <span style={{ padding: '3px 7px', borderRadius: 6, fontSize: 9, fontWeight: 700, letterSpacing: 0.4,
          background: T.glassFill, backdropFilter: 'blur(10px)', WebkitBackdropFilter: 'blur(10px)', color: T.text2,
          border: `0.5px solid ${T.glassBorder}` }}>{scan.mode.toUpperCase()}</span>
      </div>
    </div>
  );
}

// ── Sparkline ───────────────────────────────────────────────────────
function Spark({ values, w = 110, h = 30, color, fill = true }) {
  const c = color || T.accent;
  const max = Math.max(...values), min = Math.min(...values), r = (max - min) || 1;
  const pts = values.map((v, i) => [(i / (values.length - 1)) * w, h - ((v - min) / r) * (h - 5) - 2.5]);
  const d = pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`).join(' ');
  return (
    <svg width={w} height={h} style={{ display: 'block' }}>
      {fill && {/* [decorative SVG span: area fill path] */}}
      {/* [decorative SVG span: line stroke path] */}
      {/* [decorative SVG span: end dot] */}
    </svg>
  );
}

// ── Mini histogram (RGB luma, clean) ────────────────────────────────
function Histogram({ w = 180, h = 50 }) {
  const make = (off, amp) => [...Array(48)].map((_, i) => { const x = (i - 24 + off) / 12; return Math.exp(-x*x) * amp + (i*7%5)/40; });
  const chans = [['#D06A66', make(2, 0.85)], ['#5BA86E', make(0, 1)], ['#5B85C8', make(-3, 0.7)]];
  const path = arr => { let d = `M0 ${h}`; arr.forEach((v, i) => { d += ` L${((i/(arr.length-1))*w).toFixed(1)} ${(h - Math.min(1,v)*(h-2)).toFixed(1)}`; }); return d + ` L${w} ${h} Z`; };
  return (
    <svg width={w} height={h} style={{ display: 'block' }}>
      {[0.25,0.5,0.75].map((t,i) => <line key={i} x1={t*w} y1="0" x2={t*w} y2={h} stroke={T.grid} strokeWidth="0.5"/>)}
      {chans.map(([c, d], i) => <path key={i} d={path(d)} fill={c} fillOpacity="0.28" stroke={c} strokeOpacity="0.7" strokeWidth="0.9"/>)}
    </svg>
  );
}

// ── Frame strip ─────────────────────────────────────────────────────
function FrameStrip({ count = 12, sel = -1, h = 40 }) {
  const tones = [['#EFE7D7','#9B8769'],['#D8C3A4','#7A6244'],['#CBB592','#5E4B30']];
  return (
    <div style={{ display: 'flex', gap: 4, width: '100%' }}>
      {[...Array(count)].map((_, i) => {
        const rej = i === Math.floor(count * 0.34) || i === Math.floor(count * 0.72);
        const on = i === sel;
        const [a, b] = tones[i % 3];
        return (
          <div key={i} style={{ flex: 1, height: h, borderRadius: 5, position: 'relative', overflow: 'hidden',
            background: rej ? T.badSoft : `radial-gradient(circle at 38% 32%, ${a}, ${b})`,
            border: on ? `1.5px solid ${T.accent}` : rej ? `0.5px solid ${T.bad}` : `0.5px solid ${T.line}`,
            opacity: rej ? 0.7 : 1 }}>
            {rej && <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', color: T.bad, fontSize: 13, fontWeight: 700 }}>×</div>}
          </div>
        );
      })}
    </div>
  );
}

Object.assign(window, { HeroModel, CoverageDome, CoverageSphere, ScanThumb, SCAN_TONES, Spark, Histogram, FrameStrip });
