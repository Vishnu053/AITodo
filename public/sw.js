// Offline shell. API calls are never cached.
const CACHE = 'aitodo-shell-v1'
const SHELL = ['./', 'styles.css', 'app.js', 'lib/parse.js', 'lib/memory.js', 'lib/proactive.js', 'lib/ai.js', 'manifest.webmanifest', 'icons/icon-192x192.png', 'icons/favicon-32x32.png']

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()))
})
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()))
})
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url)
  if (e.request.method !== 'GET' || url.origin !== location.origin || url.pathname.includes('/api/')) return
  // Network first so deploys show up immediately; cache is the offline fallback.
  e.respondWith(fetch(e.request).then(res => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)) }
    return res
  }).catch(() => caches.match(e.request, { ignoreSearch: true }).then(r => r || caches.match('./'))))
})
self.addEventListener('notificationclick', e => {
  e.notification.close()
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then(cs => (cs[0] ? cs[0].focus() : self.clients.openWindow('./'))))
})
