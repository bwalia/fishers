/* Service worker: browser push, and the offline shell.
 *
 * It was deliberately tiny for a long time, and the warning that sat here was
 * right: a service worker intercepts every request for as long as it is
 * registered, so caching added carelessly outlives the deploy that removed it.
 * It is here now because a scorer at a ground with no signal could not open the
 * app at all — the browser showed its own offline page and the match was gone.
 *
 * So the caching below is written to be taken back. Every cache name carries
 * SHELL_VERSION; `activate` deletes every cache that is not the current one, so
 * shipping a new version evicts the old one on the next load. Bumping the
 * version to a name nothing writes to would empty the lot.
 *
 * Two rules keep it honest:
 *
 *   - Nothing under /api is ever cached. Those responses are authenticated and
 *     mutable, and a stale one is a lie about somebody's match.
 *   - Navigations go to the network first and fall back to the cache, so an
 *     online reader always gets the current page and never a stale one.
 *
 * What a scorer actually needs offline — the match and the balls they have
 * tapped — is not here. That is in IndexedDB (`src/lib/outbox.ts`), where it
 * can be reasoned about, not in an HTTP cache.
 */

const SHELL_VERSION = "v1";
const SHELL_CACHE = `fishers-shell-${SHELL_VERSION}`;
/* The page served when a navigation fails and nothing better is cached. */
const OFFLINE_FALLBACK = "/";

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL_CACHE);
      // Only the entry point. Everything else is cached as it is fetched:
      // Next's asset names carry content hashes, so a precache list written
      // here would be wrong the moment anything is rebuilt.
      await cache.add(new Request(OFFLINE_FALLBACK, { cache: "reload" })).catch(() => {});
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names.filter((n) => n.startsWith("fishers-shell-") && n !== SHELL_CACHE)
             .map((n) => caches.delete(n)),
      );
      await self.clients.claim();
    })(),
  );
});

/* Assets Next fingerprints, so a cached copy can never be the wrong one. */
function isImmutable(url) {
  return url.pathname.startsWith("/_next/static/")
    || url.pathname.endsWith(".woff2")
    || url.pathname.endsWith(".wasm");
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // Authenticated and mutable: a stale one is a lie about somebody's match.
  if (url.pathname.startsWith("/api/")) return;

  if (isImmutable(url)) {
    event.respondWith(
      (async () => {
        const hit = await caches.match(request);
        if (hit) return hit;
        const response = await fetch(request);
        if (response.ok) (await caches.open(SHELL_CACHE)).put(request, response.clone());
        return response;
      })(),
    );
    return;
  }

  // Everything else — pages, the manifest, icons — is network-first, so an
  // online reader is never shown yesterday's page.
  event.respondWith(
    (async () => {
      try {
        const response = await fetch(request);
        if (response.ok) (await caches.open(SHELL_CACHE)).put(request, response.clone());
        return response;
      } catch (err) {
        const hit = await caches.match(request);
        if (hit) return hit;
        if (request.mode === "navigate") {
          const shell = await caches.match(OFFLINE_FALLBACK);
          if (shell) return shell;
        }
        throw err;
      }
    })(),
  );
});

self.addEventListener("push", (event) => {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch {
    payload = { title: "Fishers", body: event.data.text() };
  }

  const url = payload.url || "/notifications";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      // Somebody looking at Fishers right now already sees it: the page shows
      // its own alert from the live stream, and a system notification on top
      // would say everything twice. (Chrome only insists on one when no tab
      // of the site is focused.)
      if (clients.some((c) => c.focused && c.visibilityState === "visible")) return;
      return self.registration.showNotification(payload.title || "Fishers", {
        body: payload.body || "",
        icon: "/icon-192.png",
        badge: "/badge.png",
        // Notifications about the same thing replace each other rather than
        // stacking up: four reminders about one fixture is four times the
        // annoyance and no more information.
        tag: payload.tag || url,
        // …except a chat, where a new message replacing the last one should
        // still make a sound: it is news, not a repeat.
        renotify: url.startsWith("/chat/"),
        data: { url },
      });
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = event.notification.data?.url || "/notifications";

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      // Focus a tab that already has the app open rather than opening a
      // fourth one. Somebody who taps six notifications should end up with
      // one window, not six.
      for (const client of clients) {
        if (new URL(client.url).origin === self.location.origin && "focus" in client) {
          client.navigate(target);
          return client.focus();
        }
      }
      return self.clients.openWindow(target);
    })
  );
});

/* A push subscription can be rotated by the browser without asking. When that
 * happens the old endpoint stops working, and the only warning is this event —
 * without it, push silently stops for that person and nobody finds out. */
self.addEventListener("pushsubscriptionchange", (event) => {
  event.waitUntil(
    (async () => {
      const applicationServerKey = event.oldSubscription?.options?.applicationServerKey;
      if (!applicationServerKey) return;
      const fresh = await self.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey,
      });
      // The page owns the access token, so it does the registering. Tell any
      // open tab; if none is open, the next visit re-subscribes anyway.
      const clients = await self.clients.matchAll({ includeUncontrolled: true });
      for (const client of clients) {
        client.postMessage({ type: "push-subscription-changed", subscription: fresh.toJSON() });
      }
    })()
  );
});
