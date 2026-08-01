// Service Worker v5 — network-first (dev): siempre pide a la red y cachea la
// respuesta. Cae a cache SOLO si la red falla. Evita el problema de servir
// versiones viejas de JS despues de un deploy.
const CACHE = 'onlypark-shell-v6';

self.addEventListener('install', (e) => {
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
    // Fuerza a todas las pestañas activas a recargar con la nueva version
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const c of clients) c.navigate(c.url);
  })());
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  // Supabase: siempre red directa, sin cache
  if (url.hostname.endsWith('supabase.co')) {
    e.respondWith(fetch(e.request));
    return;
  }
  // Cualquier otro recurso: network-first, cache como fallback offline
  e.respondWith((async () => {
    try {
      const resp = await fetch(e.request);
      if (resp.ok && e.request.method === 'GET') {
        const c = await caches.open(CACHE);
        c.put(e.request, resp.clone()).catch(()=>{});
      }
      return resp;
    } catch (err) {
      const cached = await caches.match(e.request);
      if (cached) return cached;
      throw err;
    }
  })());
});
