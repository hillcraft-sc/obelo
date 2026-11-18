// Handwriting ink follows the paper. A drawing always stores the four dark-paper colours; on light
// paper they are drawn in darker shades of the same role (main ink, blue, red, green). Colours
// from anywhere else are left alone. The same mapping is in ios/Shared/Notes/DrawingFormat.swift.
(function () {
  var ON_LIGHT = { '#f1f5f9': '#0f172a', '#93c5fd': '#2563eb', '#fca5a5': '#dc2626', '#86efac': '#16a34a' };
  window.obeloPaperIsDark = function () { return window.OBELO_PAPER_DARK !== false; };
  window.obeloInk = function (stored) {
    if (window.obeloPaperIsDark() || typeof stored !== 'string') return stored;
    return ON_LIGHT[stored.toLowerCase()] || stored;
  };
  // The pen swatches show the shade you will get on this paper
  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.color-btn').forEach(function (b) { b.style.background = window.obeloInk(b.dataset.color); });
  });
})();
