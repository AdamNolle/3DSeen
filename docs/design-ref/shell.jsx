// studio/shell.jsx — interactive prototype shell: device switcher, scaling, theme, screen router.

const DEVICE_DIMS = {
  phone: { w: 402, h: 874, pad: 26 },
  pad:   { w: 1194, h: 834, pad: 30 },
  mac:   { w: 1440, h: 900, pad: 30 },
};

// Per-device flow definitions (order = the natural walkthrough)
const FLOWS = {
  phone: ['library', 'mode', 'briefing', 'viewfinder', 'quality', 'review', 'compute', 'viewer', 'export', 'settings'],
  pad:   ['library', 'mode', 'briefing', 'viewfinder', 'quality', 'review', 'compute', 'viewer', 'export', 'settings'],
  mac:   ['library', 'viewer', 'compute', 'export', 'settings'],
};

const SCREEN_TITLES = {
  library: 'Library', mode: 'New Scan', briefing: 'Briefing', viewfinder: 'Capture',
  quality: 'Detail', review: 'Review', compute: 'Compute', viewer: 'Model', export: 'Export', settings: 'Settings',
};

function useViewportScale(dims, reserveTop = 92) {
  const [scale, setScale] = React.useState(1);
  React.useEffect(() => {
    const calc = () => {
      const availW = window.innerWidth - 48;
      const availH = window.innerHeight - reserveTop - 28;
      const s = Math.min(availW / dims.w, availH / dims.h, 1);
      setScale(s);
    };
    calc();
    window.addEventListener('resize', calc);
    return () => window.removeEventListener('resize', calc);
  }, [dims.w, dims.h, reserveTop]);
  return scale;
}

// Device chooser segmented control with icons
function DeviceSwitch({ device, onChange }) {
  const items = [
    { v: 'phone', icon: 'phone', label: 'iPhone' },
    { v: 'pad', icon: 'tablet', label: 'iPad' },
    { v: 'mac', icon: 'laptop', label: 'Mac' },
  ];
  return (
    <div style={{ display: 'inline-flex', padding: 3, borderRadius: 999, background: T.fieldFill, boxShadow: `inset 0 0 0 0.5px ${T.line}`, gap: 2 }}>
      {items.map(it => {
        const on = device === it.v;
        return (
          <button key={it.v} className="st-tap" onClick={() => onChange(it.v)} style={{
            height: 34, padding: '0 14px', borderRadius: 999, border: 'none', cursor: 'pointer',
            background: on ? T.card : 'transparent', color: on ? T.ink : T.text2,
            boxShadow: on ? '0 1px 3px rgba(0,0,0,0.10)' : 'none',
            fontFamily: T.sf, fontSize: 13.5, fontWeight: 600, letterSpacing: -0.1,
            display: 'flex', alignItems: 'center', gap: 7,
          }}>
            <Ic name={it.icon} s={15} c={on ? T.ink : T.text2} /> {/* [proxy-elided span; reconstructed] */}
            {it.label}
          </button>
        );
      })}
    </div>
  );
}

// Screen jump menu (dropdown)
function ScreenMenu({ device, screen, onJump }) {
  const [open, setOpen] = React.useState(false);
  const flow = FLOWS[device];
  const idx = flow.indexOf(screen);
  return (
    <div style={{ position: 'relative' }}>
      <button className="st-tap" onClick={() => setOpen(o => !o)} style={{
        height: 34, padding: '0 12px 0 14px', borderRadius: 999, border: 'none', cursor: 'pointer',
        background: T.fieldFill, color: T.ink, boxShadow: `inset 0 0 0 0.5px ${T.line}`,
        fontFamily: T.sf, fontSize: 13.5, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3 }}>{String(idx + 1).padStart(2, '0')}</span>
        {SCREEN_TITLES[screen]}
        <Ic name="chevDown" s={14} c={T.text3} /> {/* [proxy-elided span; reconstructed] */}
      </button>
      {open && (
        <>
          <div onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 40 }} />
          <div className="st-pop-in" style={{ position: 'absolute', top: 42, left: 0, zIndex: 50, width: 220, transformOrigin: 'top left' }}>
            <Glass radius={16} style={{ padding: 6 }}>
              {flow.map((s, i) => {
                const on = s === screen;
                return (
                  <button key={s} className="st-tap" onClick={() => { onJump(s); setOpen(false); }} style={{
                    width: '100%', height: 36, padding: '0 10px', borderRadius: 10, border: 'none', cursor: 'pointer',
                    background: on ? T.accentSoft : 'transparent', color: on ? T.accentText : T.ink,
                    fontFamily: T.sf, fontSize: 13.5, fontWeight: on ? 650 : 500, display: 'flex', alignItems: 'center', gap: 10, textAlign: 'left',
                  }}>
                    <span className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: on ? T.accentText : T.text4, width: 16 }}>{String(i + 1).padStart(2, '0')}</span>
                    <span style={{ flex: 1 }}>{SCREEN_TITLES[s]}</span>
                    {on && <Ic name="check" s={14} c={T.accentText} />}
                  </button>
                );
              })}
            </Glass>
          </div>
        </>
      )}
    </div>
  );
}

function Shell({ device, setDevice, screen, setScreen, dark, setDark, screens, sharedState }) {
  const dims = DEVICE_DIMS[device];
  const scale = useViewportScale(dims);
  const flow = FLOWS[device];

  const go = (s) => { if (s) setScreen(s); };
  const next = () => { const i = flow.indexOf(screen); if (i < flow.length - 1) setScreen(flow[i + 1]); };
  const prev = () => { const i = flow.indexOf(screen); if (i > 0) setScreen(flow[i - 1]); };

  const Frame = device === 'phone' ? PhoneFrame : device === 'pad' ? PadFrame : MacWindow;
  const reg = screens[device] || {};
  const ScreenComp = reg[screen] || reg.__fallback;

  return (
    <div className="st-root" style={{
      position: 'fixed', inset: 0, overflow: 'hidden',
      background: T.mode === 'dark'
        ? 'radial-gradient(130% 100% at 50% 0%, #161618, #0A0A0C)'
        : 'radial-gradient(130% 100% at 50% 0%, #F1EFEA, #DEDBD3)',
    }}>
      {/* top toolbar */}
      <div style={{ position: 'fixed', top: 16, left: 0, right: 0, zIndex: 60, display: 'flex', justifyContent: 'center', pointerEvents: 'none' }}>
        {/* [proxy-elided span: toolbar Glass containing DeviceSwitch, ScreenMenu, theme toggle, prev/next nav — not captured] */}
      </div>

      {/* device stage */}
      <div style={{ position: 'absolute', top: 92, left: 0, right: 0, bottom: 0, display: 'grid', placeItems: 'center' }}>
        <div style={{ transform: `scale(${scale})`, transformOrigin: 'center center', transition: 'transform .25s ease' }}>
          {/* [proxy-elided span: <Frame> wrapping StatusBar + <ScreenComp .../> for the active screen — not captured] */}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Shell, FLOWS, SCREEN_TITLES, DEVICE_DIMS });
