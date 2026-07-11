// studio/data.jsx — shared sample data across screens

const SCANS = [
  { id: 'celestial', name: 'Celestial Bust',  mode: 'Object',    date: 'Today',    mb: 184, tier: 'Full',    tone: 'bone',     tris: '4.2M' },
  { id: 'amaranth',  name: 'Amaranth Vase',   mode: 'Object',    date: '5d ago',   mb: 92,  tier: 'Medium',  tone: 'rust',     tris: '1.2M' },
  { id: 'studio',    name: 'Studio Floor 02', mode: 'Space',     date: '1w ago',   mb: 412, tier: 'Full',    tone: 'graphite', tris: '5.1M' },
  { id: 'desk',      name: 'Walnut Desk',     mode: 'Object',    date: '1w ago',   mb: 76,  tier: 'Reduced', tone: 'walnut',   tris: '480k' },
  { id: 'falls',     name: 'Granite Falls',   mode: 'Landscape', date: '2w ago',   mb: 1140,tier: 'Raw',     tone: 'slate',    tris: '16M' },
  { id: 'arch',      name: 'Archive Shelf',   mode: 'Space',     date: '3w ago',   mb: 264, tier: 'Full',    tone: 'ice',      tris: '3.4M' },
  { id: 'ceramic',   name: 'Ceramic Pour',    mode: 'Object',    date: '3w ago',   mb: 58,  tier: 'Preview', tone: 'bone',     tris: '120k' },
  { id: 'tape',      name: 'Cassette Maxell', mode: 'Object',    date: 'Aug 04',   mb: 124, tier: 'Full',    tone: 'graphite', tris: '4.0M' },
];

const EXPORT_FORMATS = [
  { id: 'usdz', name: 'USDZ', ext: '.usdz',    size: '184 MB', desc: 'AR Quick Look · Apple-native', best: true },
  { id: 'usd',  name: 'USD',  ext: '.usdc',    size: '212 MB', desc: 'Pixar OpenUSD · pipelines' },
  { id: 'glb',  name: 'glTF', ext: '.glb',     size: '156 MB', desc: 'Universal · web · Blender' },
  { id: 'obj',  name: 'OBJ',  ext: '.obj + mtl',size:'298 MB', desc: 'Legacy DCC interchange' },
  { id: 'fbx',  name: 'FBX',  ext: '.fbx',     size: '188 MB', desc: 'Unreal · Unity · Maya' },
  { id: 'ply',  name: 'PLY',  ext: '.ply',     size: '440 MB', desc: 'Point cloud · raw archive' },
];

const MEASUREMENTS = [
  { id: 'M01', l: 'Height · chin to crown', v: '14.20', u: 'cm' },
  { id: 'M02', l: 'Shoulder width',          v: '11.84', u: 'cm' },
  { id: 'M03', l: 'Nose to ear',             v: '3.10',  u: 'cm' },
];

const DROPS = [
  { id: 'crown', label: 'Crown of head', severity: 'high', x: 50, y: 22, hint: 'Lift camera 25° higher' },
  { id: 'earl',  label: 'Back-left ear', severity: 'med',  x: 24, y: 42, hint: 'Walk 15° clockwise' },
  { id: 'under', label: 'Underside',     severity: 'med',  x: 50, y: 84, hint: 'Tilt down 25°' },
];

Object.assign(window, { SCANS, EXPORT_FORMATS, MEASUREMENTS, DROPS });
