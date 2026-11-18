// Lists every route the app has, straight from the running Express app, so tests can't miss a new one.
function mountPath(layer) {
  if (layer.regexp.fast_slash) return '';
  return layer.regexp.source
    .replace(/^\^/, '')
    .replace(/\\\/\?\(\?=\\\/\|\$\)$/, '')
    .replace(/\\\//g, '/');
}

function walk(stack, prefix, out) {
  for (const layer of stack) {
    if (layer.route) {
      for (const method of Object.keys(layer.route.methods)) {
        if (method === '_all') continue;
        out.push({ method: method.toUpperCase(), path: prefix + layer.route.path });
      }
    } else if (layer.name === 'router' && layer.handle.stack) {
      walk(layer.handle.stack, prefix + mountPath(layer), out);
    }
  }
}

function listRoutes(app) {
  const out = [];
  walk(app._router.stack, '', out);
  return out.map((r) => ({ ...r, params: [...r.path.matchAll(/:(\w+)/g)].map((m) => m[1]) }));
}

module.exports = { listRoutes };
