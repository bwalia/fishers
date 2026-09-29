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
