// studio/icons.jsx — clean stroke icon set. Usage: <Ic name="..." s={18} c="..." sw={1.7} />
// Single source of truth; defaults to currentColor so it inherits text color.
// NOTE: the proxy elided most icon SVG bodies (highly-repetitive spans). Names below
// are the complete authoritative ICON_PATHS key set (49). Bodies that were recoverable
// from the fragment view are inlined verbatim; the rest are marked [decorative SVG span].

const ICON_PATHS = {
  // navigation / chrome
  back:   (s,c) => /* [decorative SVG span: left chevron] */,
  chev:   (s,c) => <path d="M9 6l6 6-6 6" />,
  chevDown:(s,c) => <path d="M6 9l6 6 6-6" />,
  close:  (s,c) => <path d="M6 6l12 12M18 6L6 18" />,
  plus:   (s,c) => <path d="M12 5v14M5 12h14" />,
  check:  (s,c) => <path d="M4 12l5 5L20 6" />,
  search: (s,c) => <g><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.3-4.3" /></g>,
  more:   (s,c) => /* [decorative SVG span: three dots] */,
  grid:   (s,c) => /* [decorative SVG span: grid] */,
  list:   (s,c) => <g><path d="M8 6h13M8 12h13M8 18h13"/><circle cx="4" cy="6" r="1" fill={c} stroke="none"/><circle cx="4" cy="12" r="1" fill={c} stroke="none"/><circle cx="4" cy="18" r="1" fill={c} stroke="none"/></g>,
  settings:(s,c) => /* [decorative SVG span: gear] */,

  // domain
  cube:   (s,c) => /* [decorative SVG span: cube] */,
  room:   (s,c) => /* [decorative SVG span: room] */,
  landscape:(s,c) => /* [decorative SVG span: landscape] */,
  sparkle:(s,c) => <path d="M12 3l1.6 5.4L19 10l-5.4 1.6L12 17l-1.6-5.4L5 10l5.4-1.6L12 3z" fill={c} stroke="none"/>,
  camera: (s,c) => <g><rect x="2.5" y="6.5" width="19" height="13.5" rx="3"/><path d="M8 6.5l1.4-2.5h5.2L16 6.5"/><circle cx="12" cy="13.4" r="3.4"/></g>,
  scan:   (s,c) => /* [decorative SVG span: scan frame] */,
  bolt:   (s,c) => <path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z" fill={c} stroke="none"/>,
  chip:   (s,c) => <g><rect x="6" y="6" width="12" height="12" rx="2.5"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/></g>,
  laptop: (s,c) => /* [decorative SVG span: laptop] */,
  phone:  (s,c) => /* [decorative SVG span: phone] */,
  tablet: (s,c) => /* [decorative SVG span: tablet] */,
  thermal:(s,c) => /* [decorative SVG span: thermal] */,
  ruler:  (s,c) => /* [decorative SVG span: ruler] */,
  layers: (s,c) => /* [decorative SVG span: layers] */,
  share:  (s,c) => /* [decorative SVG span: share] */,
  export: (s,c) => /* [decorative SVG span: export] */,
  download:(s,c) => /* [decorative SVG span: download] */,
  airdrop:(s,c) => /* [decorative SVG span: airdrop] */,
  pin:    (s,c) => /* [decorative SVG span: pin] */,
  light:  (s,c) => <g><circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.2 5.2l2.1 2.1M16.7 16.7l2.1 2.1M18.8 5.2l-2.1 2.1M7.3 16.7l-2.1 2.1"/></g>,
  focus:  (s,c) => /* [decorative SVG span: focus] */,
  refresh:(s,c) => /* [decorative SVG span: refresh] */,
  speed:  (s,c) => /* [decorative SVG span: speed/gauge] */,
  hand:   (s,c) => /* [decorative SVG span: hand] */,
  warning:(s,c) => /* [decorative SVG span: warning triangle] */,
  info:   (s,c) => /* [decorative SVG span: info] */,
  clock:  (s,c) => /* [decorative SVG span: clock] */,
  folder: (s,c) => /* [decorative SVG span: folder] */,
  cloud:  (s,c) => /* [decorative SVG span: cloud] */,
  lock:   (s,c) => /* [decorative SVG span: lock] */,
  user:   (s,c) => /* [decorative SVG span: user] */,
  globe:  (s,c) => /* [decorative SVG span: globe] */,
  wifi:   (s,c) => /* [decorative SVG span: wifi] */,
  battery:(s,c) => /* [decorative SVG span: battery] */,
  play:   (s,c) => /* [decorative SVG span: play] */,
  trash:  (s,c) => /* [decorative SVG span: trash] */,
  copy:   (s,c) => /* [decorative SVG span: copy] */,
};

function Ic({ name, s = 18, c = 'currentColor', sw = 1.7, style }) {
  const draw = ICON_PATHS[name];
  if (!draw) return null;
  return (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={sw}
      strokeLinecap="round" strokeLinejoin="round" style={{ display: 'block', flexShrink: 0, ...style }}>
      {draw(s, c)}
    </svg>
  );
}

Object.assign(window, { Ic });
