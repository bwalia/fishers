/// Browser push, from the page's side.
///
/// Three separate things have to line up: a registered service worker, the
/// user's permission, and a subscription posted to the server. Any of them can
/// be missing independently — somebody can grant permission and then clear
/// site data, leaving a permission with no subscription — so the state is
/// worked out by asking, never remembered.

import { api } from "@/lib/api";

export type PushState =
  /// The browser cannot do this at all: no service workers, no Push API, or
  /// an insecure origin. Safari on iOS also needs the site installed first.
  | "unsupported"
  /// The server has no VAPID keys, so there is nothing to subscribe to.
  | "unconfigured"
  | "denied"
  | "off"
  | "on";

type KeyResponse = { enabled: boolean; public_key: string | null };

export function pushSupported(): boolean {
  return (
    typeof window !== "undefined" &&
    "serviceWorker" in navigator &&
    "PushManager" in window &&
    "Notification" in window &&
    // Push needs a secure context. Over plain HTTP on a LAN — which is how
    // this app is often reached at a ground — it simply is not available.
    window.isSecureContext
  );
}

/// What the browser and server between them can actually do right now.
export async function pushState(): Promise<PushState> {
  if (!pushSupported()) return "unsupported";

  const key = await api<KeyResponse>("GET", "/notifications/web-push-key", undefined, false)
    .catch(() => null);
  if (!key?.enabled || !key.public_key) return "unconfigured";
  if (Notification.permission === "denied") return "denied";

  const registration = await navigator.serviceWorker.getRegistration("/sw.js");
  const existing = await registration?.pushManager.getSubscription();
  return existing ? "on" : "off";
}

/// Ask for permission and subscribe. Returns the state it ended in, so a
/// caller never has to guess whether a refused prompt counted.
export async function enablePush(): Promise<PushState> {
  if (!pushSupported()) return "unsupported";

  const key = await api<KeyResponse>("GET", "/notifications/web-push-key", undefined, false);
  if (!key.enabled || !key.public_key) return "unconfigured";

  // Registering the worker first: asking for permission and *then* finding
  // there is nothing to receive the push is a prompt spent for nothing.
  const registration = await navigator.serviceWorker.register("/sw.js");
  await navigator.serviceWorker.ready;

  if ((await Notification.requestPermission()) !== "granted") {
    return Notification.permission === "denied" ? "denied" : "off";
  }

  const subscription = await registration.pushManager.subscribe({
    // Required by Chrome: every push must result in something the person sees.
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(key.public_key),
  });

  await api("POST", "/notifications/register-device", {
    device_token: JSON.stringify(subscription.toJSON()),
    platform: "web",
  });
  return "on";
}

/// Unsubscribe here and forget it on the server.
///
/// Both, in that order: dropping the server row while the browser stays
/// subscribed means the push service keeps a live endpoint nobody sends to,
/// and the person cannot turn it back on because the browser thinks it is
/// already on.
export async function disablePush(): Promise<PushState> {
  const registration = await navigator.serviceWorker.getRegistration("/sw.js");
  const subscription = await registration?.pushManager.getSubscription();
  if (subscription) {
    const token = JSON.stringify(subscription.toJSON());
    await subscription.unsubscribe();
    await api("POST", "/notifications/unregister-device", { device_token: token })
      .catch(() => {
        // The row will be reaped on the next 410 anyway.
      });
  }
  return "off";
}

/// The VAPID key arrives as base64url text and `subscribe` wants bytes.
///
/// Typed as `ArrayBuffer` rather than `Uint8Array`: a `Uint8Array` can be
/// backed by a `SharedArrayBuffer`, which `applicationServerKey` will not
/// take, and TypeScript is right to say so.
function urlBase64ToUint8Array(base64url: string): ArrayBuffer {
  const padded = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}
