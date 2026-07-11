// studio/frames.jsx — device chrome: iPhone, iPad, macOS window + status bars + stage

// ── iPhone ───────────────────────────────────────────────────────────────────
function PhoneFrame({ children, w = 402, h = 874 }) {
  return (
    <div className="st-root" style={{
      width: w, height: h, borderRadius: 56, position: 'relative', background: '#000',
      boxShadow: '0 50px 110px rgba(20,20,30,0.30), 0 0 0 2px #2a2a2e, 0 0 0 12px #08080a, 0 0 0 13px rgba(255,255,255,0.05)',
    }}>
      <div style={{ position: 'absolute', inset: 0, borderRadius: 56, overflow: 'hidden', background: T.bg }}>
        {children}
      </div>
      {/* dynamic island */}
      <div style={{ position: 'absolute', top: 12, left: '50%', transform: 'translateX(-50%)', width: 122, height: 35, borderRadius: 22, background: '#000', zIndex: 200 }} />
      {/* home indicator */}
      <div style={{ position: 'absolute', bottom: 9, left: '50%', transform: 'translateX(-50%)', width: 138, height: 5, borderRadius: 99, background: T.mode === 'dark' ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.32)', zIndex: 150, pointerEvents: 'none' }} />
    </div>
  );
}

// ── iPad ───────────────────────────────────────────────────────────────────
function PadFrame({ children, w = 1194, h = 834 }) {
  return (
    <div className="st-root" style={{
      width: w, height: h, borderRadius: 34, position: 'relative', background: '#000',
      boxShadow: '0 70px 130px rgba(20,20,30,0.34), 0 0 0 2px #2a2a2e, 0 0 0 13px #08080a, 0 0 0 14px rgba(255,255,255,0.05)',
    }}>
      <div style={{ position: 'absolute', inset: 0, borderRadius: 34, overflow: 'hidden', background: T.bg }}>
        {children}
      </div>
      <div style={{ position: 'absolute', top: '50%', right: 7, transform: 'translateY(-50%)', width: 5, height: 5, borderRadius: 99, background: '#1d1d20', zIndex: 200 }} />
    </div>
  );
}

// ── macOS window ───────────────────────────────────────────────────────────────────
function MacWindow({ children, w = 1440, h = 900, title = '3DSeen Studio' }) {
  const titleBarH = 0; // app uses its own integrated toolbar; we just draw traffic lights overlay
  return (
    <div className="st-root" style={{
      width: w, height: h, borderRadius: 14, position: 'relative', background: T.bg, overflow: 'hidden',
      border: `0.5px solid ${T.mode === 'dark' ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.12)'}`,
      boxShadow: '0 60px 140px rgba(20,20,30,0.40), 0 0 0 0.5px rgba(0,0,0,0.10), 0 20px 50px rgba(0,0,0,0.20)',
    }}>
      {children}
      {/* traffic lights — drawn over the app's own toolbar (overlaid title bar style) */}
      <div style={{ position: 'absolute', top: 19, left: 20, display: 'flex', gap: 8, zIndex: 300 }}>
        {['#FF5F57', '#FEBC2E', '#28C840'].map((c, i) => (
          <div key={i} style={{ width: 12, height: 12, borderRadius: 99, background: c, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.12)' }} />
        ))}
      </div>
    </div>
  );
}

// ── iOS status bar (theme + tone aware) ───────────────────────────────
function StatusBar({ time = '9:41', tone, dark }) {
  const isDark = dark !== undefined ? dark : (T.mode === 'dark');
  const c = tone === 'light' ? '#fff' : tone === 'dark' ? '#000' : (isDark ? '#fff' : '#000');
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, height: 54, zIndex: 100, pointerEvents: 'none',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '18px 34px 0',
    }}>
      <span className="st-num" style={{ fontSize: 16, fontWeight: 600, color: c, letterSpacing: -0.3 }}>{time}</span>
      <div style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
        <svg width="18" height="11" viewBox="0 0 18 11"><rect x="0" y="7" width="3" height="4" rx=".7" fill={c}/><rect x="5" y="4.5" width="3" height="6.5" rx=".7" fill={c}/><rect x="10" y="2" width="3" height="9" rx=".7" fill={c}/><rect x="15" y="0" width="3" height="11" rx=".7" fill={c}/></svg>
        <svg width="16" height="11" viewBox="0 0 16 11" fill={c}><path d="M8 3.4c1.9 0 3.7.7 5 1.9l1-1A8 8 0 008 2a8 8 0 00-6 2.3l1 1A7 7 0 018 3.4z"/><path d="M8 6.2c1.1 0 2 .4 2.8 1.1l1-1A6 6 0 008 4.9a6 6 0 00-3.8 1.4l1 1A4 4 0 018 6.2zM8 9.4a1.4 1.4 0 100-2.8 1.4 1.4 0 000 2.8z"/></svg>
        <svg width="25" height="12" viewBox="0 0 25 12"><rect x=".5" y=".5" width="21" height="11" rx="3" stroke={c} strokeOpacity=".35" fill="none"/><rect x="2" y="2" width="16" height="8" rx="1.5" fill={c}/><path d="M23.5 4v4c.7-.3 1.2-1.1 1.2-2s-.5-1.7-1.2-2z" fill={c} fillOpacity=".5"/></svg>
      </div>
    </div>
  );
}

// ── iPad status bar ───────────────────────────────────────────────────────────────────
function PadStatusBar({ left = '9:41 AM · Wed 16 Sep', tone }) {
  const c = tone === 'light' ? '#fff' : (T.mode === 'dark' ? '#fff' : T.ink);
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, height: 28, zIndex: 100, pointerEvents: 'none',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 24px 0',
      fontSize: 13, fontWeight: 600, color: c, letterSpacing: -0.1,
    }}>
      <span className="st-num">{left}</span>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
        <svg width="15" height="9" viewBox="0 0 18 11"><rect x="0" y="7" width="3" height="4" rx=".7" fill={c}/><rect x="5" y="4.5" width="3" height="6.5" rx=".7" fill={c}/><rect x="10" y="2" width="3" height="9" rx=".7" fill={c}/><rect x="15" y="0" width="3" height="11" rx=".7" fill={c}/></svg>
        <svg width="22" height="10" viewBox="0 0 25 12"><rect x=".5" y=".5" width="21" height="11" rx="3" stroke={c} strokeOpacity=".35" fill="none"/><rect x="2" y="2" width="16" height="8" rx="1.5" fill={c}/><path d="M23.5 4v4c.7-.3 1.2-1.1 1.2-2s-.5-1.7-1.2-2z" fill={c} fillOpacity=".5"/></svg>
      </div>
    </div>
  );
}

// ── Stage: clean neutral studio backdrop for 3D content ─────────────
function Stage({ children, style = {}, radius = 0, soft = false }) {
  return (
    <div style={{ position: 'absolute', inset: 0, borderRadius: radius, overflow: 'hidden', background: T.stage, ...style }}>
      {/* soft top key light */}
      <div style={{ position: 'absolute', inset: 0, background: `radial-gradient(80% 55% at 50% -5%, ${T.stageRim}, transparent 60%)` }} />
      {/* faint floor reflection band */}
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: '38%', background: T.mode === 'dark' ? 'linear-gradient(to top, rgba(0,0,0,0.25), transparent)' : 'linear-gradient(to top, rgba(0,0,0,0.05), transparent)' }} />
      {children}
    </div>
  );
}

Object.assign(window, { PhoneFrame, PadFrame, MacWindow, StatusBar, PadStatusBar, Stage });
