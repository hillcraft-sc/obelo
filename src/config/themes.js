const BUILT_IN_THEMES = [
  {
    id: 'dark',
    label: 'Dark',
    desc: 'Classic dark',
    isDark: true,
    preview: { bg: '#0f1117', surface: '#1a1d27', border: '#2e3349', accent: '#2563eb' },
  },
  {
    id: 'midnight',
    label: 'Midnight',
    desc: 'Deep indigo',
    isDark: true,
    preview: { bg: '#0a0b12', surface: '#13151f', border: '#272a3e', accent: '#7c3aed' },
  },
  {
    id: 'forest',
    label: 'Forest',
    desc: 'Earthy green',
    isDark: true,
    preview: { bg: '#0d1a0f', surface: '#162419', border: '#28402d', accent: '#15803d' },
  },
  {
    id: 'mocha',
    label: 'Mocha',
    desc: 'Warm coffee',
    isDark: true,
    preview: { bg: '#1c1410', surface: '#261c15', border: '#3d2b1f', accent: '#b45309' },
  },
  {
    id: 'sunset',
    label: 'Sunset',
    desc: 'Warm amber glow',
    isDark: true,
    preview: { bg: '#1a0f0f', surface: '#231616', border: '#3e2520', accent: '#b94528' },
  },
  {
    id: 'amoled',
    label: 'AMOLED',
    desc: 'Pure black',
    isDark: true,
    preview: { bg: '#000000', surface: '#0d0d0d', border: '#1c1c1c', accent: '#3b82f6' },
  },
  {
    id: 'ctp-frappe',
    label: 'Catppuccin Frappé',
    desc: 'Muted pastel dark',
    isDark: true,
    preview: { bg: '#292c3c', surface: '#303446', border: '#414559', accent: '#ca9ee6' },
  },
  {
    id: 'ctp-macchiato',
    label: 'Catppuccin Macchiato',
    desc: 'Deeper pastel dark',
    isDark: true,
    preview: { bg: '#1e2030', surface: '#24273a', border: '#363a4f', accent: '#c6a0f6' },
  },
  {
    id: 'ctp-mocha',
    label: 'Catppuccin Mocha',
    desc: 'Darkest pastel',
    isDark: true,
    preview: { bg: '#181825', surface: '#1e1e2e', border: '#313244', accent: '#cba6f7' },
  },
  {
    id: 'light',
    label: 'Light',
    desc: 'Clean white',
    isDark: false,
    preview: { bg: '#f8fafc', surface: '#ffffff', border: '#e2e8f0', accent: '#1e5fcc' },
  },
  {
    id: 'breeze',
    label: 'Breeze',
    desc: 'Cool sky blue',
    isDark: false,
    preview: { bg: '#dce9f7', surface: '#eef5fd', border: '#93c4e8', accent: '#0059b3' },
  },
  {
    id: 'ctp-latte',
    label: 'Catppuccin Latte',
    desc: 'Soft pastel light',
    isDark: false,
    preview: { bg: '#dce0e8', surface: '#eff1f5', border: '#ccd0da', accent: '#8839ef' },
  },
];

const DARK_THEME_IDS = new Set(BUILT_IN_THEMES.filter(t => t.isDark).map(t => t.id));
const VALID_THEME_IDS = new Set([...BUILT_IN_THEMES.map(t => t.id), 'custom']);

function isDarkTheme(themeId, customBase) {
  if (!themeId) return true;
  if (themeId === 'custom') return customBase !== 'light';
  return DARK_THEME_IDS.has(themeId);
}

// Handwriting paper: the saved choice ('theme' by default, 'dark' or 'white') and whether the
// paper is dark. Ink shades and ground colours follow from that (public/js/note-editor.js,
// DrawingRenderer in ios/Shared).
const NOTE_PAPERS = ['theme', 'dark', 'white'];
function notePaperChoice(prefs) {
  return NOTE_PAPERS.includes(prefs && prefs.notePaper) ? prefs.notePaper : 'theme';
}
function isPaperDark(prefs) {
  const choice = notePaperChoice(prefs);
  if (choice === 'dark') return true;
  if (choice === 'white') return false;
  return isDarkTheme(prefs && prefs.theme, prefs && prefs.customBase);
}

function hexAdjust(hex, delta) {
  const c = hex.replace('#', '');
  const clamp = v => Math.min(255, Math.max(0, v));
  const r = clamp(parseInt(c.slice(0, 2), 16) + delta);
  const g = clamp(parseInt(c.slice(2, 4), 16) + delta);
  const b = clamp(parseInt(c.slice(4, 6), 16) + delta);
  return `#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
}

function hexToRgb(hex) {
  const c = hex.replace('#', '');
  return {
    r: parseInt(c.slice(0, 2), 16),
    g: parseInt(c.slice(2, 4), 16),
    b: parseInt(c.slice(4, 6), 16),
  };
}

// Returns CSS variable declarations for a custom accent color
function customAccentVars(accent, isDark) {
  if (!accent || !/^#[0-9a-f]{6}$/i.test(accent)) return null;
  const { r, g, b } = hexToRgb(accent);
  const hover  = hexAdjust(accent, isDark ? 25 : -20);
  const darker = hexAdjust(accent, -35);
  // text colors: lighter on dark bg, darker on light bg for contrast
  const light  = hexAdjust(accent, isDark ? 70 : -15);
  const muted  = hexAdjust(accent, isDark ? 100 : -35);
  const { r: hr, g: hg, b: hb } = hexToRgb(hover);
  return [
    `--ca: ${accent}`,
    `--ca-hover: ${hover}`,
    `--ca-dark: ${darker}`,
    `--ca-light: ${light}`,
    `--ca-muted: ${muted}`,
    `--ca-r: ${r}`,
    `--ca-g: ${g}`,
    `--ca-b: ${b}`,
    `--ca-hr: ${hr}`,
    `--ca-hg: ${hg}`,
    `--ca-hb: ${hb}`,
  ].join('; ');
}

module.exports = { NOTE_PAPERS, notePaperChoice, isPaperDark, BUILT_IN_THEMES, DARK_THEME_IDS, VALID_THEME_IDS, isDarkTheme, hexToRgb, customAccentVars };
