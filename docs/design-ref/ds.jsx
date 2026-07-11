// studio/ds.jsx — 3DSeen "Studio" design system (overhaul)
// Precise-instrument aesthetic: bright, legible, one cobalt accent, refined Liquid Glass.
// Two themes. T is a live token bag screens read directly; setTheme() mutates in place.

// ── token sets ──────────────────────────────────────────────────────
const LIGHT = {
  mode: 'light',
  // surfaces
  canvas: '#E9E7E1',            // desktop / behind device frames
  bg: '#F6F5F2',               // app page background (warm paper)
  bgInset: '#EDEBE5',          // recessed wells
  card: '#FFFFFF',             // raised cards
  card2: '#FBFAF8',            // secondary card
  // text
  ink: '#1B1B1D',
  text2: 'rgba(27,27,29,0.60)',
  text3: 'rgba(27,27,29,0.40)',
  text4: 'rgba(27,27,29,0.26)',
  onAccent: '#FFFFFF',
  // structure
  line: 'rgba(20,20,24,0.08)',
  lineStrong: 'rgba(20,20,24,0.14)',
  fieldFill: 'rgba(20,20,24,0.045)',
  fieldFillHi: 'rgba(20,20,24,0.075)',
  // accent (refined cobalt) + tints
  accent: '#2D68F0',
  accentText: '#1F58DC',       // accent legible as text on white
  accentSoft: 'rgba(45,104,240,0.10)',
  accentLine: 'rgba(45,104,240,0.30)',
  // status (muted, readable on white)
  good: '#1E8E5A', goodSoft: 'rgba(30,142,90,0.12)',
  warn: '#B6791D', warnSoft: 'rgba(182,121,29,0.14)',
  bad: '#C53B30',  badSoft: 'rgba(197,59,48,0.12)',
  // glass (floating controls)
  glassFill: 'rgba(255,255,255,0.72)',
  glassBorder: 'rgba(20,20,24,0.07)',
  glassShine: 'rgba(255,255,255,0.9)',
  glassShadow: '0 1px 2px rgba(20,20,30,0.06), 0 12px 32px rgba(20,20,30,0.10)',
  // cards
  cardShadow: '0 1px 2px rgba(20,20,30,0.04), 0 10px 30px rgba(20,20,30,0.06)',
  cardShadowLg: '0 2px 6px rgba(20,20,30,0.05), 0 24px 60px rgba(20,20,30,0.10)',
  // primary button
  primaryFill: '#1B1B1D',
  primaryText: '#FFFFFF',
  primaryShadow: '0 1px 2px rgba(0,0,0,0.18), 0 6px 16px rgba(0,0,0,0.16)',
  // stage for 3D content
  stage: 'radial-gradient(125% 110% at 50% 8%, #FCFCFB 0%, #EFEEE9 52%, #E2E0DA 100%)',
  stageRim: 'rgba(255,255,255,0.6)',
  // chart strokes
  grid: 'rgba(20,20,24,0.07)',
  axis: 'rgba(20,20,24,0.16)',
  // type
  sf: '"SF Pro Display","SF Pro Text",-apple-system,BlinkMacSystemFont,system-ui,sans-serif',
  mono: '"SF Mono",ui-monospace,"JetBrains Mono",Menlo,monospace',
};

const DARK = {
  ...LIGHT,
  mode: 'dark',
  canvas: '#0C0C0E',
  bg: '#161619',
  bgInset: '#101013',
  card: '#1F1F25',
  card2: '#1A1A1F',
  ink: '#F3F2F5',
  text2: 'rgba(243,242,245,0.62)',
  text3: 'rgba(243,242,245,0.40)',
  text4: 'rgba(243,242,245,0.24)',
  onAccent: '#0A1124',
  line: 'rgba(255,255,255,0.08)',
  lineStrong: 'rgba(255,255,255,0.15)',
  fieldFill: 'rgba(255,255,255,0.06)',
  fieldFillHi: 'rgba(255,255,255,0.10)',
  accent: '#5E9BFF',
  accentText: '#84B2FF',
  accentSoft: 'rgba(94,155,255,0.16)',
  accentLine: 'rgba(94,155,255,0.34)',
  good: '#34C77B', goodSoft: 'rgba(52,199,123,0.16)',
  warn: '#E0A53F', warnSoft: 'rgba(224,165,63,0.16)',
  bad: '#FF6B5E',  badSoft: 'rgba(255,107,94,0.16)',
  glassFill: 'rgba(34,34,40,0.66)',
  glassBorder: 'rgba(255,255,255,0.10)',
  glassShine: 'rgba(255,255,255,0.14)',
  glassShadow: '0 1px 2px rgba(0,0,0,0.4), 0 16px 40px rgba(0,0,0,0.5)',
  cardShadow: '0 1px 2px rgba(0,0,0,0.3), 0 12px 34px rgba(0,0,0,0.42)',
  cardShadowLg: '0 2px 8px rgba(0,0,0,0.4), 0 28px 70px rgba(0,0,0,0.55)',
  primaryFill: '#F3F2F5',
  primaryText: '#16161A',
  primaryShadow: '0 1px 2px rgba(0,0,0,0.4), 0 8px 20px rgba(0,0,0,0.4)',
  stage: 'radial-gradient(125% 110% at 50% 6%, #2A2A31 0%, #17171B 55%, #101013 100%)',
  stageRim: 'rgba(255,255,255,0.10)',
  grid: 'rgba(255,255,255,0.07)',
  axis: 'rgba(255,255,255,0.18)',
};

const T = { ...LIGHT };
function setTheme(mode) {
  const src = mode === 'dark' ? DARK : LIGHT;
  Object.keys(T).forEach(k => { if (!(k in src)) delete T[k]; });
  Object.assign(T, src);
}

// warm stone palette for rendered objects (theme-independent, premium not neon)
const STONE = { hi: '#ECE4D6', mid: '#BFA98C', lo: '#6B5C49', deep: '#372E24' };

// ── one-time global CSS ─────────────────────────────────────────────
if (typeof document !== 'undefined' && !document.getElementById('studio-css')) {
  const s = document.createElement('style');
  s.id = 'studio-css';
  s.textContent = `
    @keyframes st-fade { from { opacity: 0 } to { opacity: 1 } }
    @keyframes st-rise { from { opacity: 0; transform: translateY(10px) } to { opacity: 1; transform: none } }
    @keyframes st-pop { 0% { opacity:0; transform: scale(.96) } 100% { opacity:1; transform: none } }
    @keyframes st-sheen { 0% { transform: translateX(-120%) } 100% { transform: translateX(260%) } }
    @keyframes st-spin { to { transform: rotate(360deg) } }
    @keyframes st-pulse { 0%,100% { opacity:.5 } 50% { opacity:1 } }
    @keyframes st-orbit { to { transform: rotate(360deg) } }
    .st-root { -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
    .st-root * { box-sizing: border-box; }
    .st-tap { cursor: pointer; transition: transform .12s ease, background .15s ease, box-shadow .2s ease, opacity .15s ease; -webkit-tap-highlight-color: transparent; }
    .st-tap:active { transform: scale(.97); }
    .st-scroll::-webkit-scrollbar { width: 0; height: 0; }
    .st-scroll { scrollbar-width: none; }
    .st-num { font-variant-numeric: tabular-nums; }

    /* Entrances resolve to a fully-visible resting state with NO dependency on
       the animation clock (some capture/offscreen contexts freeze
       document.timeline, which would otherwise strand from-0 keyframes or
       @starting-style transitions at opacity 0). Live viewers still get the
       clock-driven micro-motion elsewhere; first paint is always visible. */
    .st-screen-in { opacity: 1; transform: none; }
    .st-sheet-in { transform: translateY(0); opacity: 1; }
    .st-modal-in { transform: scale(1); opacity: 1; }
    .st-pop-in { transform: scale(1); opacity: 1; transform-origin: top left; }
    .st-rise-in { opacity: 1; transform: none; }
  `;
  document.head.appendChild(s);
}

// ── Glass: Liquid Glass floating panel ──────────────────────────────
// Apple's Liquid Glass language: a translucent lens that blurs + saturates
// the backdrop, catches a bright specular highlight along its top curve, and
// carries a faint edge-light + soft inner shade for depth. tone="dark" is for
// glass that floats over a dark surface (e.g. the camera feed) — it darkens the
// lens so light content stays legible while still refracting the scene.
function Glass({ children, radius = 18, style = {}, className = '', onClick, blur = 24, tone = 'auto', shine = true }) {
  const dark = tone === 'dark';
  const fill = dark ? 'rgba(26,24,21,0.52)' : T.glassFill;
  const border = dark ? 'rgba(255,255,255,0.18)' : T.glassBorder;
  const shadow = dark
    ? '0 2px 8px rgba(0,0,0,0.32), 0 20px 50px rgba(0,0,0,0.42)'
    : T.glassShadow;
  const rimTop = dark ? 'rgba(255,255,255,0.55)' : T.glassShine;
  const sheen = dark ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.38)';
  const innerShade = dark ? 'rgba(0,0,0,0.28)' : 'rgba(18,18,28,0.05)';
  return (
    <div className={className} onClick={onClick} style={{
      position: 'relative', borderRadius: radius, background: fill, isolation: 'isolate',
      backdropFilter: `blur(${blur}px) saturate(200%) brightness(${dark ? 1.05 : 1.02})`,
      WebkitBackdropFilter: `blur(${blur}px) saturate(200%) brightness(${dark ? 1.05 : 1.02})`,
      border: `0.5px solid ${border}`, boxShadow: shadow, ...style,
    }}>
      {shine && <div style={{
        position: 'absolute', inset: 0, borderRadius: radius, pointerEvents: 'none',
        // specular top rim + faint inner light-fall + soft bottom shade = the "lens"
        boxShadow: `inset 0 0.9px 0 ${rimTop}, inset 0 0 0 0.5px ${dark ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.25)'}, inset 0 -10px 22px ${innerShade}`,
        background: `linear-gradient(177deg, ${sheen} 0%, transparent 26%)`,
      }} />}
      {children}
    </div>
  );
}

// ── Card: solid raised surface ──────────────────────────────────────
function Card({ children, radius = 20, pad = 0, style = {}, className = '', onClick, elevated = false, inset = false }) {
  return (
    <div className={className} onClick={onClick} style={{
      borderRadius: radius, padding: pad,
      background: inset ? T.bgInset : T.card,
      border: `0.5px solid ${T.line}`,
      boxShadow: inset ? 'none' : (elevated ? T.cardShadowLg : T.cardShadow),
      ...style,
    }}>{children}</div>
  );
}

// ── Button ──────────────────────────────────────────────────────────
function Button({ children, kind = 'secondary', size = 'md', style = {}, onClick, full = false }) {
  const h = size === 'lg' ? 52 : size === 'sm' ? 36 : 44;
  const fs = size === 'lg' ? 16 : size === 'sm' ? 13.5 : 15;
  const pad = size === 'sm' ? '0 14px' : '0 20px';
  const base = {
    height: h, padding: pad, borderRadius: 999, border: 'none', cursor: 'pointer',
    fontFamily: T.sf, fontSize: fs, fontWeight: 600, letterSpacing: -0.2,
    display: full ? 'flex' : 'inline-flex', width: full ? '100%' : undefined,
    alignItems: 'center', justifyContent: 'center', gap: 8, whiteSpace: 'nowrap',
    transition: 'transform .12s ease, background .15s, box-shadow .2s',
  };
  const skins = {
    primary: { background: T.primaryFill, color: T.primaryText, boxShadow: T.primaryShadow },
    accent: { background: T.accent, color: T.onAccent, boxShadow: `0 1px 2px rgba(0,0,0,0.12), 0 6px 16px ${T.accentSoft}` },
    secondary: { background: T.fieldFill, color: T.ink, boxShadow: `inset 0 0 0 0.5px ${T.line}` },
    ghost: { background: 'transparent', color: T.text2 },
    glass: { background: T.glassFill, color: T.ink, backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)', boxShadow: `inset 0 0 0 0.5px ${T.glassBorder}, ${T.glassShadow}` },
  };
  return (
    <button className="st-tap" onClick={onClick} style={{ ...base, ...skins[kind], ...style }}>{children}</button>
  );
}

// ── Eyebrow / overline label ────────────────────────────────────────
function Label({ children, color, style = {} }) {
  return (
    <div style={{
      fontFamily: T.mono, fontSize: 10.5, fontWeight: 600, letterSpacing: 1.4,
      textTransform: 'uppercase', color: color || T.text3, ...style,
    }}>{children}</div>
  );
}

// ── Stat: keyed numeric readout (sans, tabular — no serif) ──────────
function Stat({ k, v, unit, c, size = 'md', align = 'left' }) {
  const fs = size === 'xl' ? 40 : size === 'lg' ? 28 : size === 'sm' ? 17 : 22;
  return (
    <div style={{ minWidth: 0, textAlign: align }}>
      <div style={{ fontFamily: T.mono, fontSize: 9.5, fontWeight: 600, letterSpacing: 1, color: T.text3, textTransform: 'uppercase' }}>{k}</div>
      <div className="st-num" style={{
        fontSize: fs, fontWeight: 680, color: c || T.ink, letterSpacing: -0.6, lineHeight: 1.04, marginTop: 3,
        display: 'flex', alignItems: 'baseline', gap: 3, justifyContent: align === 'right' ? 'flex-end' : 'flex-start',
      }}>
        {v}{unit && <span style={{ fontSize: fs * 0.46, fontWeight: 600, color: T.text3, letterSpacing: 0 }}>{unit}</span>}
      </div>
    </div>
  );
}

// ── Segmented control ───────────────────────────────────────────────
function Segmented({ options, value, onChange, size = 'md', style = {} }) {
  const h = size === 'sm' ? 30 : 36;
  return (
    <div style={{
      display: 'inline-flex', padding: 3, borderRadius: 999, background: T.fieldFill,
      boxShadow: `inset 0 0 0 0.5px ${T.line}`, gap: 2, ...style,
    }}>
      {options.map(o => {
        const val = typeof o === 'string' ? o : o.value;
        const lab = typeof o === 'string' ? o : o.label;
        const on = val === value;
        return (
          <button key={val} className="st-tap" onClick={() => onChange && onChange(val)} style={{
            height: h, padding: '0 14px', borderRadius: 999, border: 'none', cursor: 'pointer',
            background: on ? T.card : 'transparent', color: on ? T.ink : T.text2,
            boxShadow: on ? '0 1px 2px rgba(0,0,0,0.10), 0 1px 4px rgba(0,0,0,0.06)' : 'none',
            fontFamily: T.sf, fontSize: size === 'sm' ? 12.5 : 13.5, fontWeight: 600, letterSpacing: -0.1,
            display: 'flex', alignItems: 'center', gap: 6,
          }}>{lab}</button>
        );
      })}
    </div>
  );
}

// ── Toggle switch ───────────────────────────────────────────────────
function Toggle({ on, onChange }) {
  return (
    <div className="st-tap" onClick={() => onChange && onChange(!on)} style={{
      width: 50, height: 30, borderRadius: 99, padding: 2, flexShrink: 0,
      display: 'flex', justifyContent: on ? 'flex-end' : 'flex-start', alignItems: 'center',
      background: on ? T.good : T.fieldFillHi, transition: 'background .2s',
      boxShadow: on ? 'none' : `inset 0 0 0 0.5px ${T.line}`,
    }}>
      <div style={{ width: 26, height: 26, borderRadius: 99, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)' }} />
    </div>
  );
}

// ── Pill / chip ─────────────────────────────────────────────────────
function Chip({ children, tone = 'neutral', style = {} }) {
  const tones = {
    neutral: { bg: T.fieldFill, fg: T.text2, line: T.line },
    accent: { bg: T.accentSoft, fg: T.accentText, line: T.accentLine },
    good: { bg: T.goodSoft, fg: T.good, line: 'transparent' },
    warn: { bg: T.warnSoft, fg: T.warn, line: 'transparent' },
    bad: { bg: T.badSoft, fg: T.bad, line: 'transparent' },
  };
  const t = tones[tone] || tones.neutral;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5, padding: '4px 10px', borderRadius: 999,
      background: t.bg, color: t.fg, border: `0.5px solid ${t.line}`,
      fontFamily: T.sf, fontSize: 12, fontWeight: 600, letterSpacing: -0.1, ...style,
    }}>{children}</span>
  );
}

// ── Meter bar ───────────────────────────────────────────────────────
function Meter({ value = 0.5, color, track, height = 6, radius = 99 }) {
  return (
    <div style={{ height, borderRadius: radius, background: track || T.fieldFillHi, overflow: 'hidden' }}>
      <div style={{ height: '100%', width: `${Math.max(0, Math.min(1, value)) * 100}%`, background: color || T.accent, borderRadius: radius, transition: 'width .5s cubic-bezier(.2,.7,.2,1)' }} />
    </div>
  );
}

// ── Progress ring ───────────────────────────────────────────────────
function Ring({ value = 0.8, size = 72, stroke = 7, color, label, sub }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <div style={{ position: 'relative', width: size, height: size, flexShrink: 0 }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={T.fieldFillHi} strokeWidth={stroke} />
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={color || T.accent} strokeWidth={stroke}
          strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c * (1 - value)}
          style={{ transition: 'stroke-dashoffset .7s cubic-bezier(.2,.7,.2,1)' }} />
      </svg>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
        {label !== undefined && <div className="st-num" style={{ fontSize: size * 0.3, fontWeight: 700, color: T.ink, letterSpacing: -0.5, lineHeight: 1 }}>{label}</div>}
        {sub && <div style={{ fontFamily: T.mono, fontSize: 8.5, fontWeight: 600, color: T.text3, letterSpacing: 1, marginTop: 2 }}>{sub}</div>}
      </div>
    </div>
  );
}

// ── Hairline divider ────────────────────────────────────────────────
function Rule({ vertical = false, style = {} }) {
  return <div style={{ background: T.line, ...(vertical ? { width: 0.5, alignSelf: 'stretch' } : { height: 0.5, width: '100%' }), ...style }} />;
}

Object.assign(window, {
  T, LIGHT, DARK, setTheme, STONE,
  Glass, Card, Button, Label, Stat, Segmented, Toggle, Chip, Meter, Ring, Rule,
});
