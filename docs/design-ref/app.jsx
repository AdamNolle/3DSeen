// studio/app.jsx — orchestrator: state, screen registry, theme. Renders the Shell.

function Placeholder({ device }) {
  const screenName = 'This screen';
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, display: 'grid', placeItems: 'center', padding: 40 }}>
      <div style={{ textAlign: 'center', maxWidth: 360 }}>
        <div style={{ width: 60, height: 60, borderRadius: 18, background: T.accentSoft, display: 'grid', placeItems: 'center', margin: '0 auto 18px' }}>
          <Ic name="sparkle" s={26} c={T.accent} /> {/* [proxy-elided span; reconstructed] */}
        </div>
        <div style={{ fontSize: 22, fontWeight: 720, letterSpacing: -0.5, color: T.ink }}>Designing next</div>
        <div style={{ fontSize: 14, color: T.text2, marginTop: 8, lineHeight: 1.5 }}>
          The hero screens — Library, Capture, the 3D Model viewer and the full Export flow — are ready across {device === 'mac' ? 'Mac' : device === 'pad' ? 'iPad' : 'iPhone'}. This screen is part of the next build pass.
        </div>
      </div>
    </div>
  );
}

const SCREENS = {
  phone: {
    library: PhoneLibrary, mode: PhoneModePicker, briefing: PhoneBriefing, viewfinder: PhoneViewfinder,
    quality: PhoneQuality, review: PhoneReview, compute: PhoneCompute, viewer: PhoneViewer,
    export: PhoneExport, settings: PhoneSettings,
    __fallback: Placeholder,
  },
  pad: {
    library: PadLibrary, mode: PadModePicker, briefing: PadBriefing, viewfinder: PadViewfinder,
    quality: PadQuality, review: PadReview, compute: PadCompute, viewer: PadViewer,
    export: PadExport, settings: PadSettings,
    __fallback: Placeholder,
  },
  mac: {
    library: MacLibrary, viewer: MacViewer, compute: MacCompute, export: MacExport, settings: MacSettings,
    __fallback: Placeholder,
  },
};

function App() {
  const [device, setDeviceRaw] = React.useState('phone');
  const [screen, setScreen] = React.useState('library');
  const [dark, setDark] = React.useState(false);

  setTheme(dark ? 'dark' : 'light');

  const setDevice = (d) => {
    setDeviceRaw(d);
    // keep the screen if it's part of the new device's flow, else go home
    if (!FLOWS[d].includes(screen)) setScreen('library');
  };

  return (
    <Shell device={device} setDevice={setDevice} screen={screen} setScreen={setScreen} dark={dark} setDark={setDark} screens={SCREENS} /> {/* [proxy-elided span; reconstructed] */}
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
