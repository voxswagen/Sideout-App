/* Sideout Society — service worker.
   Two jobs: make the app installable (Chrome will not offer to install
   without one), and keep it usable when the court wifi drops.

   It used to be network-first with the cache as a fallback, on the grounds
   that a stale roster is worse than a slow one. That reasoning was sound and
   aimed at the wrong thing: every piece of live data in this app — the
   roster, the session, the ladder, the feed — comes from Supabase, which is
   a different origin and never reaches this worker at all. All this handles
   is the shell: one HTML file, the manifest and the icons. Serving that from
   cache cannot serve a stale roster, because it has never served a roster.

   So the shell is cache-first and revalidated in the background, which is
   what makes the app open at all on a court with one bar. The version bump
   below still forces the new build: `activate` bins every other cache, and
   the background fetch replaces the copy for next time.

   Everything else is network-first with a short timeout, because a request
   that hangs for thirty seconds on bad wifi is worse than one that fails in
   three and falls back to what we already have.                          */

/* Bump this on every deploy that changes CSS or markup. The activate
   handler deletes any cache that is not the current name, so a new
   name is what actually forces phones onto the new build — without
   it, an installed app can serve last week's stylesheet indefinitely. */
const CACHE = 'sideout-v148';
const SHELL = ['/', '/index.html', '/manifest.json',
               '/icon-192.png', '/icon-512.png', '/icon-maskable.png',
               '/apple-touch-icon.png',
               /* The club's mark. It is the first thing on the sign-in
                  screen, so a phone opening the app off the cache should not
                  have to wait on the network to see whose app this is. */
               '/sos-mark.png'];

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

/* A response worth keeping. An error page cached under the app's own URL is
   how an app comes back from a blip permanently broken. */
function keepable(res){
  return res && res.ok && (res.type === 'basic' || res.type === 'default');
}

/* Network, but not for ever. Court wifi does not usually refuse a request —
   it accepts it and never answers, and the browser will wait a very long
   time for that. */
function within(ms, req){
  return new Promise((resolve, reject) =>{
    const t = setTimeout(()=> reject(new Error('slow')), ms);
    fetch(req).then(r =>{ clearTimeout(t); resolve(r); },
                    e =>{ clearTimeout(t); reject(e); });
  });
}

self.addEventListener('fetch', ev =>{
  const req = ev.request;
  if(req.method !== 'GET') return;
  const url = new URL(req.url);
  if(url.origin !== location.origin) return;      /* Supabase talks for itself */

  /* Anything that loads the app itself — a navigation, or index.html asked
     for directly — is answered from the cache straight away and refreshed
     behind the back of it. This is the whole of the offline story: the app
     opens, and then everything it shows is asked of Supabase, which either
     answers or is reported as not having answered. */
  const isShell = req.mode === 'navigate'
    || url.pathname === '/' || url.pathname === '/index.html';

  if(isShell){
    ev.respondWith(
      caches.match('/index.html').then(hit =>{
        const fresh = within(8000, req).then(res =>{
          if(keepable(res)){
            const copy = res.clone();
            caches.open(CACHE).then(c => c.put('/index.html', copy)).catch(()=>{});
          }
          return res;
        });
        /* A cached copy answers now; the fetch above still runs and lands in
           the cache for next time. With no cached copy there is nothing to
           do but wait for the network. */
        if(hit){ fresh.catch(()=>{}); return hit; }
        return fresh;
      })
    );
    return;
  }

  ev.respondWith(
    within(8000, req)
      .then(res =>{
        if(keepable(res)){
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(()=>{});
        }
        return res;
      })
      .catch(()=> caches.match(req).then(hit => hit || caches.match('/index.html')))
  );
});

/* Let the page ask for the newest build rather than waiting for a reload.
   The app calls this when it comes back from being offline. */
self.addEventListener('message', ev =>{
  if(ev.data === 'refresh-shell'){
    caches.open(CACHE).then(c => c.add('/index.html')).catch(()=>{});
  }
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
