// Note folders, shared by the web workspace (routes/notes.js) and the JSON API (routes/api.js).
// Folders can nest. A note sits in one folder, or at the top level when folderId is null.

const prisma = require('../lib/prisma');

// Sets `path` on each folder to its full path ("Work / Projects") for pickers and labels
function folderPaths(folders) {
  const byId = new Map(folders.map((f) => [f.id, f]));
  for (const f of folders) {
    const parts = [];
    let cur = f;
    const seen = new Set();
    while (cur && !seen.has(cur.id)) {
      seen.add(cur.id);
      parts.unshift(cur.name);
      cur = cur.parentId ? byId.get(cur.parentId) : null;
    }
    f.path = parts.join(' / ');
  }
  return folders;
}

// Flattens folders and notes into rows in tree order, each row knowing its depth and the ids of
// the folders above it (so the page can hide a collapsed folder's rows)
function buildFolderTree(folders, notes) {
  const childFolders = new Map();
  for (const f of folders) {
    const key = f.parentId ?? 0;
    if (!childFolders.has(key)) childFolders.set(key, []);
    childFolders.get(key).push(f);
  }
  const notesIn = new Map();
  for (const n of notes) {
    const key = n.folderId ?? 0;
    if (!notesIn.has(key)) notesIn.set(key, []);
    notesIn.get(key).push(n);
  }
  const rows = [];
  const walk = (parentId, depth, ancestors) => {
    for (const f of childFolders.get(parentId) || []) {
      rows.push({ kind: 'folder', id: f.id, name: f.name, depth, parentId: f.parentId, ancestors });
      walk(f.id, depth + 1, [...ancestors, f.id]);
    }
    for (const n of notesIn.get(parentId) || []) {
      rows.push({ kind: 'note', note: n, depth, ancestors });
    }
  };
  walk(0, 0, []);
  return rows;
}

// Folder id from input, or null for the top level (missing, '' or 'null').
// Returns undefined when it isn't one of this user's folders.
async function ownFolderId(raw, userId) {
  if (raw === undefined || raw === null || raw === '' || raw === 'null') return null;
  const id = Number(raw);
  if (!Number.isInteger(id)) return undefined;
  const folder = await prisma.folder.findFirst({ where: { id, userId } });
  return folder ? folder.id : undefined;
}

// Deletes a folder. Its notes and subfolders move up one level; nothing else is deleted.
async function deleteFolderKeepContents(folder, userId) {
  await prisma.$transaction([
    prisma.note.updateMany({ where: { userId, folderId: folder.id }, data: { folderId: folder.parentId } }),
    prisma.folder.updateMany({ where: { userId, parentId: folder.id }, data: { parentId: folder.parentId } }),
    prisma.folder.delete({ where: { id: folder.id } }),
  ]);
}

module.exports = { folderPaths, buildFolderTree, ownFolderId, deleteFolderKeepContents };
