/// A v4 UUID that also works away from localhost.
///
/// `crypto.randomUUID` is gated on a secure context, so it is undefined over
/// plain HTTP on a LAN address — which is exactly how a scorer reaches this
/// app from a phone at the ground, and how the iOS app's host is addressed.
/// `crypto.getRandomValues` carries no such gate, so build the same shape from
/// it instead.
///
/// The randomness matters: these ids are the server's deduplication key for
/// scoring events and the scorer's device lock, so a collision would drop a
/// delivery from the book. Math.random is not an acceptable source for that,
/// which is why the last resort here is to fail loudly rather than guess.
export function randomUUID(): string {
  const c: Crypto | undefined = globalThis.crypto;

  if (typeof c?.randomUUID === "function") return c.randomUUID();

  if (typeof c?.getRandomValues !== "function") {
    throw new Error(
      "This browser exposes no secure random source, so scoring ids cannot be " +
        "generated safely. Use a browser with Web Crypto, or reach the app over HTTPS."
    );
  }

  const b = new Uint8Array(16);
  c.getRandomValues(b);
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 1 (RFC 4122)

  const hex = Array.from(b, (n) => n.toString(16).padStart(2, "0")).join("");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}
