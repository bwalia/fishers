/// The pay link's small pure helpers: which `/p/<token>` is a pay link, how a
/// screenshot is sized down, and the WhatsApp address a message goes to.
///
/// Kept free of the API client and the dictionary so `npm test` can import it
/// directly — `node --test` strips the types but cannot follow `@/` imports.

/// `/p/<token>` serves two kinds of link. A player's profile link is exactly
/// 24 letters and digits (`users.rs`, `share_link`); a pay link is 38
/// characters of base64url (`services/pay_links.rs`), and may hold `-` and `_`.
/// Anything that is not a profile token is treated as a pay link, so a pay
/// link with a character changed or cut off still lands on the friendly
/// "this link isn't right" page rather than a sign-in screen.
export function isProfileToken(token: string): boolean {
  return /^[A-Za-z0-9]{24}$/.test(token);
}

/// Whether a path is a public pay page, which carries none of the app's
/// navigation: whoever opens it may never have signed in.
export function isPayLinkPath(pathname: string): boolean {
  if (/^\/pay\/[^/]+\/?$/.test(pathname)) return true;
  const m = /^\/p\/([^/]+)\/?$/.exec(pathname);
  if (!m) return false;
  let token = m[1];
  try {
    token = decodeURIComponent(token);
  } catch {
    /* a malformed escape is still not a profile token */
  }
  return !isProfileToken(token);
}

/// The size to draw a picture at so neither side passes `max`, keeping its
/// shape. Never scales up.
export function fitWithin(width: number, height: number, max: number): { width: number; height: number } {
  if (width <= 0 || height <= 0) return { width: 1, height: 1 };
  const scale = Math.min(1, max / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

/// A WhatsApp message ready to send: the app opens with the text written and
/// asks who to send it to. Only ever given the server's own bill and reminder
/// messages — never bank details, which do not belong in a URL.
export function whatsappUrl(text: string): string {
  return `https://wa.me/?text=${encodeURIComponent(text)}`;
}

/// A short, stable fingerprint of a string (FNV-1a, 32 bits). Used to
/// remember "you've paid these details before" without keeping the details
/// themselves in the browser's storage.
export function fingerprint(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0");
}

/// "Aman" from "Aman Gill".
export function firstName(name: string): string {
  return name.trim().split(/\s+/)[0] ?? name;
}

/// The surname as a reference would show it: "SHARMA" from "Ravi Sharma".
export function surnameRef(name: string): string {
  const words = name.trim().split(/\s+/);
  return (words[words.length - 1] ?? "").toUpperCase();
}
