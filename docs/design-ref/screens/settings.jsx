// studio/screens/settings.jsx — settings / profile (iPhone · iPad · Mac)

const SETTINGS = [
  { sec: 'Capture defaults', icon: 'camera', rows: [
    { l: 'Default mode', v: 'Auto-Pilot', i: 'sparkle' },
    { l: 'Default detail tier', v: 'Medium', i: 'layers' },
    { l: 'Audio shutter cue', i: 'bolt', toggle: true },
    { l: 'Haptic coaching', i: 'hand', toggle: true },
  ] },
  { sec: 'Compute & handoff', icon: 'chip', rows: [
    { l: 'Auto-handoff to Mac when available', i: 'laptop', toggle: true },
    { l: 'Thermal protection', v: 'Auto-pause', i: 'thermal' },
    { l: 'Background processing', v: 'Allow', i: 'chip' },
    { l: 'Color management', v: 'Display P3', i: 'light' },
  ] },
  { sec: 'Storage', icon: 'download', rows: [
    { l: 'Keep Raw archive on device', v: 'Latest 5', i: 'download' },
    { l: 'iCloud backup', i: 'cloud', toggle: true },
    { l: 'Smart offload', v: '> 30 days', i: 'refresh', toggle: true },
  ] },
  { sec: 'Privacy', icon: 'lock', rows: [
    { l: 'Location in scan metadata', i: 'pin', toggle: false },
    { l: 'On-device AI only', i: 'sparkle', toggle: true },
    { l: 'Anonymous improvement', i: 'info', toggle: false },
  ] },
];

const DEVICES = [
  { l: "Adam's MBP", s: 'Wi-Fi · M4 Max', on: true },
  { l: 'Studio Mini', s: 'Wired · M2', on: false },
];

function Avatar({ s = 54 }) {
  return (
    <div style={{ width: s, height: s, borderRadius: 99, background: `radial-gradient(circle at 32% 28%, ${T.accent}, #1B3A8C)`, display: 'grid', placeItems: 'center', boxShadow: `inset 0 1px 1px rgba(255,255,255,0.4), 0 2px 8px ${T.accentSoft}`, flexShrink: 0 }}>
      <span style={{ fontSize: s * 0.4, fontWeight: 700, color: '#fff' }}>A</span>
    </div>
  );
}

function SettingRow({ row, onToggle }) {
  const [on, setOn] = React.useState(!!row.toggle);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 0' }}>
      <div style={{ width: 30, height: 30, borderRadius: 9, background: T.fieldFill, display: 'grid', placeItems: 'center', boxShadow: `inset 0 0 0 0.5px ${T.line}`, flexShrink: 0 }}>
        <Ic name={row.i} s={16} c={T.text2} />
      </div>
      <div style={{ flex: 1, minWidth: 0, fontSize: 14, fontWeight: 500, color: T.ink, letterSpacing: -0.2 }}>{row.l}</div>
      {row.toggle !== undefined
        ? <Toggle on={on} onChange={setOn} />
        : <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ fontSize: 13.5, color: T.text2 }}>{row.v}</span><Ic name="chev" s={14} c={T.text4} /></div>}
    </div>
  );
}

function Section({ sec }) {
  return (
    <Card radius={20} style={{ padding: '4px 16px' }}>
      {sec.rows.map((r, i) => (
        <React.Fragment key={r.l}><SettingRow row={r} />{i < sec.rows.length - 1 && <Rule />}</React.Fragment>
      ))}
    </Card>
  );
}

// ─── iPhone ─────────────────────────────────────────────────────────
function PhoneSettings({ go }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <StatusBar />
      <div className="st-scroll" style={{ position: 'absolute', inset: 0, top: 54, overflow: 'auto', padding: '8px 20px 40px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button className="st-tap" onClick={() => go('library')} style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="back" s={17} c={T.text2} /></button>
          <Chip tone="neutral">Settings</Chip>
          <button className="st-tap" style={{ width: 36, height: 36, borderRadius: 999, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="info" s={16} c={T.text2} /></button>
        </div>
        <Card radius={24} style={{ padding: 18, marginTop: 16, display: 'flex', alignItems: 'center', gap: 14 }}>
          <Avatar />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 18, fontWeight: 720, letterSpacing: -0.4, color: T.ink }}>Adam Nolle</div>
            <div className="st-num" style={{ fontFamily: T.mono, fontSize: 11, color: T.text3, marginTop: 2 }}>3DSeen STUDIO · v2.4.1</div>
          </div>
          <Chip tone="accent" style={{ fontSize: 10, fontWeight: 700 }}>PRO</Chip>
        </Card>
        {SETTINGS.map(sec => (
          <div key={sec.sec}>
            <Label style={{ padding: '18px 4px 8px' }}>{sec.sec}</Label>
            <Section sec={sec} />
          </div>
        ))}
        <Label style={{ padding: '18px 4px 8px' }}>Connected</Label>
        <Card radius={20} style={{ padding: '4px 16px' }}>
          {DEVICES.map((d, i) => (
            <React.Fragment key={d.l}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 0' }}>
                <div style={{ width: 30, height: 30, borderRadius: 9, background: d.on ? T.goodSoft : T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="laptop" s={16} c={d.on ? T.good : T.text3} /></div>
                <div style={{ flex: 1 }}><div style={{ fontSize: 14, fontWeight: 600, color: T.ink }}>{d.l}</div><div className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text3, marginTop: 1 }}>{d.s}</div></div>
                {d.on && <Chip tone="good" style={{ fontSize: 10 }}>Active</Chip>}
              </div>
              {i < DEVICES.length - 1 && <Rule />}
            </React.Fragment>
          ))}
        </Card>
      </div>
    </div>
  );
}

// ─── iPad ───────────────────────────────────────────────────────────
function PadSettings({ go }) {
  const [active, setActive] = React.useState(0);
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg }}>
      <PadStatusBar />
      <div style={{ position: 'absolute', inset: 0, top: 30, display: 'flex', gap: 18, padding: 24 }}>
        {/* sidebar */}
        <div style={{ width: 272, flexShrink: 0, display: 'flex', flexDirection: 'column', gap: 14 }}>
          <Card radius={22} style={{ padding: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <Avatar s={56} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 16, fontWeight: 720, letterSpacing: -0.3, color: T.ink }}>Adam Nolle</div>
                <div className="st-num" style={{ fontFamily: T.mono, fontSize: 10, color: T.text3, marginTop: 1 }}>adam@nolle.studio</div>
                <Chip tone="accent" style={{ fontSize: 9, marginTop: 5 }}>PRO · ARCHIVAL</Chip>
              </div>
            </div>
            <Rule style={{ margin: '14px 0' }} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              {SETTINGS.map((sec, i) => {
                const on = i === active;
                return (
                  <button key={sec.sec} className="st-tap" onClick={() => setActive(i)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 10px', borderRadius: 11, border: 'none', cursor: 'pointer', background: on ? T.fieldFillHi : 'transparent', textAlign: 'left' }}>
                    <Ic name={sec.icon} s={16} c={on ? T.accent : T.text2} />
                    <span style={{ flex: 1, fontSize: 13.5, fontWeight: on ? 650 : 500, color: on ? T.ink : T.text2 }}>{sec.sec}</span>
                    <span className="st-num" style={{ fontFamily: T.mono, fontSize: 10.5, color: T.text3 }}>{sec.rows.length}</span>
                  </button>
                );
              })}
              {['Account', 'Plan & billing', 'About'].map(s => (
                <button key={s} className="st-tap" style={{ display: 'flex', alignItems: 'center', padding: '9px 10px', borderRadius: 11, border: 'none', cursor: 'pointer', background: 'transparent', textAlign: 'left' }}>
                  <span style={{ flex: 1, fontSize: 13.5, fontWeight: 500, color: T.text2 }}>{s}</span><Ic name="chev" s={13} c={T.text4} />
                </button>
              ))}
            </div>
          </Card>
          <Card radius={20} style={{ padding: 16 }}>
            <Label color={T.good}>Connected</Label>
            <div style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 12 }}>
              {DEVICES.map(d => (
                <div key={d.l} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div style={{ width: 28, height: 28, borderRadius: 8, background: d.on ? T.goodSoft : T.fieldFill, display: 'grid', placeItems: 'center' }}><Ic name="laptop" s={14} c={d.on ? T.good : T.text3} /></div>
                  <div style={{ flex: 1 }}><div style={{ fontSize: 12.5, fontWeight: 600, color: T.ink }}>{d.l}</div><div className="st-num" style={{ fontFamily: T.mono, fontSize: 10, color: T.text3 }}>{d.s}</div></div>
                  {d.on && <span style={{ width: 8, height: 8, borderRadius: 99, background: T.good }} />}
                </div>
              ))}
            </div>
          </Card>
        </div>
        {/* main */}
        <div className="st-scroll" style={{ flex: 1, overflow: 'auto', minWidth: 0 }}>
          <Label color={T.accentText}>3DSeen · {SETTINGS[active].sec}</Label>
          <div style={{ fontSize: 38, fontWeight: 730, letterSpacing: -1.4, color: T.ink, marginTop: 6, lineHeight: 1.02 }}>{SETTINGS[active].sec}</div>
          <div style={{ fontSize: 13.5, color: T.text2, marginTop: 8 }}>Settings that apply to every new scan unless overridden in the briefing.</div>
          <div style={{ marginTop: 18 }}><Section sec={SETTINGS[active]} /></div>
          {/* second column glance at all sections */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginTop: 18 }}>
            {SETTINGS.filter((_, i) => i !== active).map(sec => (
              <div key={sec.sec}>
                <Label style={{ padding: '0 4px 8px' }}>{sec.sec}</Label>
                <Section sec={sec} />
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Mac (preferences window) ───────────────────────────────────────
function MacSettings({ go }) {
  const [active, setActive] = React.useState(0);
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, display: 'flex' }}>
      {/* sidebar */}
      <div style={{ width: 248, flexShrink: 0, background: T.card2, borderRight: `0.5px solid ${T.line}`, padding: '52px 14px 18px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '4px 8px 14px' }}>
          <Avatar s={44} />
          <div style={{ minWidth: 0 }}><div style={{ fontSize: 14.5, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>Adam Nolle</div><div className="st-num" style={{ fontFamily: T.mono, fontSize: 9.5, color: T.text3 }}>PRO · ARCHIVAL</div></div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {SETTINGS.map((sec, i) => {
            const on = i === active;
            return (
              <button key={sec.sec} className="st-tap" onClick={() => setActive(i)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '8px 10px', borderRadius: 9, border: 'none', cursor: 'pointer', background: on ? T.accent : 'transparent', textAlign: 'left' }}>
                <Ic name={sec.icon} s={16} c={on ? T.onAccent : T.text2} />
                <span style={{ flex: 1, fontSize: 13.5, fontWeight: on ? 600 : 500, color: on ? T.onAccent : T.ink }}>{sec.sec}</span>
              </button>
            );
          })}
          <Rule style={{ margin: '8px 8px' }} />
          {['Account', 'Plan & billing', 'Devices', 'About'].map(s => (
            <button key={s} className="st-tap" style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '8px 10px', borderRadius: 9, border: 'none', cursor: 'pointer', background: 'transparent', textAlign: 'left' }}>
              <span style={{ flex: 1, fontSize: 13.5, fontWeight: 500, color: T.text2 }}>{s}</span>
            </button>
          ))}
        </div>
        <div style={{ flex: 1 }} />
        <Card inset radius={14} style={{ padding: 13 }}>
          <Label color={T.good}>Connected</Label>
          {DEVICES.map((d, i) => (
            <div key={d.l} style={{ display: 'flex', alignItems: 'center', gap: 9, marginTop: i ? 10 : 10 }}>
              <span style={{ width: 8, height: 8, borderRadius: 99, background: d.on ? T.good : T.text4, flexShrink: 0 }} />
              <span style={{ flex: 1, fontSize: 12.5, fontWeight: 600, color: T.ink }}>{d.l}</span>
              <span className="st-num" style={{ fontFamily: T.mono, fontSize: 9.5, color: T.text3 }}>{d.s.split(' · ')[1]}</span>
            </div>
          ))}
        </Card>
      </div>
      {/* main */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <div style={{ height: 52, flexShrink: 0, borderBottom: `0.5px solid ${T.line}`, display: 'flex', alignItems: 'center', gap: 12, padding: '0 22px', background: T.card2 }}>
          <button className="st-tap" onClick={() => go('library')} style={{ height: 30, padding: '0 10px', borderRadius: 8, border: 'none', cursor: 'pointer', background: T.fieldFill, display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 600, color: T.text2 }}><Ic name="back" s={15} c={T.text2} /> Library</button>
          <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: -0.3, color: T.ink }}>{SETTINGS[active].sec}</div>
          <div style={{ flex: 1 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 32, padding: '0 12px', borderRadius: 9, background: T.fieldFill, width: 220, boxShadow: `inset 0 0 0 0.5px ${T.line}` }}><Ic name="search" s={15} c={T.text3} /><span style={{ fontSize: 13, color: T.text3 }}>Search settings</span></div>
        </div>
        <div className="st-scroll" style={{ flex: 1, overflow: 'auto', padding: 28 }}>
          <div style={{ maxWidth: 720, margin: '0 auto' }}>
            <Label color={T.accentText}>3DSeen Studio · Preferences</Label>
            <div style={{ fontSize: 30, fontWeight: 730, letterSpacing: -1, color: T.ink, marginTop: 6 }}>{SETTINGS[active].sec}</div>
            <div style={{ fontSize: 14, color: T.text2, marginTop: 8, lineHeight: 1.45 }}>Defaults applied to every new scan and handoff. Override per-project in the capture briefing.</div>
            <div style={{ marginTop: 20 }}><Section sec={SETTINGS[active]} /></div>
            {active === 0 && (
              <div style={{ marginTop: 22 }}>
                <Label style={{ padding: '0 4px 8px' }}>Also in capture defaults</Label>
                <Section sec={SETTINGS[1]} />
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhoneSettings, PadSettings, MacSettings });
