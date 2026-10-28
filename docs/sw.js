const CACHE_NAME = 'korreturnos-pwa-v8';
const ASSETS = [
  './',
  './index.html',
  './app.js',
  './manifest.json',
  './sql-wasm.js',
  './sql-wasm.wasm',
  './datos.db',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.map((k) => (k !== CACHE_NAME ? caches.delete(k) : null)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => {
      return (
        cached ||
        fetch(event.request).then((resp) => {
          return resp;
        })
      );
    })
  );
});
