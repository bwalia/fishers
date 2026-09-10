/* Service worker for browser push.
 *
 * Deliberately tiny and does nothing else. A service worker intercepts every
 * request the page makes for as long as it is registered, so anything clever
 * added here — caching, offline shells — outlives the deploy that removed it
 * and is very hard to take back. This one only listens for pushes.
 */

self.addEventListener("push", (event) => {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch {
    payload = { title: "Fishers", body: event.data.text() };
  }

  event.waitUntil(
    self.registration.showNotification(payload.title || "Fishers", {
      body: payload.body || "",
      icon: "/icon-192.png",
      badge: "/badge.png",
      // Notifications about the same thing replace each other rather than
      // stacking up: four reminders about one fixture is four times the
      // annoyance and no more information.
      tag: payload.tag || payload.url || "fishers",
      renotify: false,
      data: { url: payload.url || "/notifications" },
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
