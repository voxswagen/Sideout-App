/* Sideout Society — service worker.
   Two jobs: make the app installable (Chrome will not offer to install
   without one), and keep it usable when the court wifi drops.

   Network first, cache as a fallback. A pickleball night is live data:
   a stale roster is worse than a slow one, so the network always gets
   first refusal and the cache only answers when it cannot.            */

/* Bump this on every deploy that changes CSS or markup. The activate
   handler deletes any cache that is not the current name, so a new
   name is what actually forces phones onto the new build — without
   it, an installed app can serve last week's stylesheet indefinitely. */
const CACHE = 'sideout-v22';
const SHELL = ['/', '/index.html', '/manifest.json',
               '/icon-192.png', '/icon-512.png', '/icon-maskable.png',
               '/apple-touch-icon.png'];

self.addEventListener('install', ev =>{
  ev.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL)).catch(()=>{})
      .then(()=> self.skipWaiting())
  );
});

self.addEventListener('activate', ev =>{
  ev.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(()=> self.clients.claim())
  );
});

self.addEventListener('fetch', ev =>{
  const req = ev.request;
  if(req.method !== 'GET') return;
  const url = new URL(req.url);
  if(url.origin !== location.origin) return;      /* Supabase talks for itself */

  ev.respondWith(
    fetch(req)
      .then(res =>{
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy)).catch(()=>{});
        return res;
      })
      .catch(()=> caches.match(req).then(hit => hit || caches.match('/index.html')))
  );
});
