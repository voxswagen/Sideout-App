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
const CACHE = 'sideout-v32';
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

/* ── push ────────────────────────────────────────────────────────
   This is the half that runs when the app is not open. The phone wakes the
   worker, hands it the message, and whatever showNotification puts up is
   what lands on the lock screen.

   The event must not resolve before showNotification does, or some browsers
   post their own "This site has been updated in the background" instead —
   hence waitUntil around the whole thing.

   On iPhone none of this happens unless the app has been added to the Home
   Screen. That is Apple's rule, not ours: a page open in Safari gets no
   push at all, however the subscription was made.                        */
self.addEventListener('push', ev =>{
  let d = {};
  try{ d = ev.data ? ev.data.json() : {}; }catch(e){ d = {}; }

  const title = d.title || 'Sideout Society';
  const body  = d.body  || '';
  ev.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      /* one session, one notification: a roster filling up should update the
         same line rather than stack fifteen of them down the screen */
      tag: d.tag || 'sideout',
      renotify: true,
      data: { url: d.url || '/' }
    })
  );
});

/* Tapping it should land on the thing it was about. If a window is already
   open, that one is focused and steered rather than a second one opened. */
self.addEventListener('notificationclick', ev =>{
  ev.notification.close();
  const want = (ev.notification.data && ev.notification.data.url) || '/';
  ev.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list =>{
      for(const c of list){
        if('focus' in c){
          if('navigate' in c) c.navigate(want).catch(()=>{});
          return c.focus();
        }
      }
      return self.clients.openWindow(want);
    })
  );
});
