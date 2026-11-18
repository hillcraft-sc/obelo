function fmtHHMM(hhmm, use12h = true) {
  if (!hhmm) return '';
  if (!use12h) return hhmm;
  const [h, m] = hhmm.split(':').map(Number);
  const ampm = h >= 12 ? 'PM' : 'AM';
  const h12 = h % 12 || 12;
  return `${h12}:${String(m).padStart(2, '0')} ${ampm}`;
}

function prefsHour12(prefs) {
  return (prefs?.timeFormat || '12h') !== '24h';
}

module.exports = { fmtHHMM, prefsHour12 };
