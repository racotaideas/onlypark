// Service Worker mínimo v1 — cache-first para el shell, network-first para la API.
const CACHE = 'onlypark-shell-v3';
const SHELL = ['/', '/index.html', '/css/app.css', '/js/main.js', '/manifest.webmanifest'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  // API de Supabase → siempre red (con fallback opcional a cache).
  if (url.hostname.endsWith('supabase.co')) {
    e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
    return;
  }
  // Shell → cache-first.
  e.respondWith(caches.match(e.request).then((r) => r || fetch(e.request)));
});
