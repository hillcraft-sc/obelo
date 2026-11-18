// priority is stored as text, so ordering by it in the database is alphabetical
// (none > medium > low > high). Sort by rank in JS instead.
const PRIORITY_RANK = { high: 3, medium: 2, low: 1, none: 0 };

// Comparator: highest priority first
const byPriority = (a, b) => (PRIORITY_RANK[b.priority] || 0) - (PRIORITY_RANK[a.priority] || 0);

module.exports = { PRIORITY_RANK, byPriority };
