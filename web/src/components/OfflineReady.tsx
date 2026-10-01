"use client";

import { useEffect } from "react";

/// Registers the service worker so the app opens without a network.
///
/// It used to be registered only when somebody switched push notifications on,
/// which meant the offline shell existed for the handful of people who had —
/// and a scorer who had declined notifications got the browser's own offline
/// page at the ground. Registering it is not asking for anything: no prompt,
/// no permission, and the push code still registers it itself for the people
/// who arrive that way.
export function OfflineReady() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    // Never in development. The worker treats everything under /_next/static/
    // as immutable and serves it cache-first, which is true of a production
    // build and false of `next dev`: there the chunks keep stable names like
    // /_next/static/chunks/app/layout.js and are rewritten in place on every
    // edit. A worker registered once then serves yesterday's chunk against
    // today's server-rendered HTML — which showed up as an English navigation
    // hydrating onto a Punjabi page, and would equally serve stale code for
    // any change at all.
    //
    // Unregistering rather than just skipping: a developer who already has one
    // installed is the person hitting this, and they should not have to find
    // it in devtools.
    if (process.env.NODE_ENV !== "production") {
      navigator.serviceWorker.getRegistrations().then((rs) => {
        rs.forEach((r) => r.unregister());
      }).catch(() => {});
      caches?.keys().then((names) => {
        names.filter((n) => n.startsWith("fishers-shell-")).forEach((n) => caches.delete(n));
      }).catch(() => {});
      return;
    }

    // After load, so it never competes with the first paint for bandwidth.
    const register = () => {
      navigator.serviceWorker.register("/sw.js").catch(() => {
        // An unregistrable worker is not a reason to break the page. The app
        // works online exactly as before; it just will not work offline.
      });
    };
    if (document.readyState === "complete") register();
    else {
      window.addEventListener("load", register, { once: true });
      return () => window.removeEventListener("load", register);
    }
  }, []);

  return null;
}
