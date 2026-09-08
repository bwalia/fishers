/// Copy text to the clipboard, including away from localhost.
///
/// `navigator.clipboard` is gated on a secure context, so the whole object is
/// undefined over plain HTTP on a LAN address — which is exactly how a scorer
/// reaches this app from a phone at the ground. Calling it there threw
/// "Cannot read properties of undefined (reading 'writeText')", which names
/// nothing anyone can act on, and took the freshly minted share link down with
/// it.
///
/// `document.execCommand("copy")` is deprecated but carries no secure-context
/// gate, so it is the fallback. Failure is reported rather than thrown: the
/// caller still holds the link and can show it to be copied by hand, which is
/// the one outcome that always works.
export async function copyText(text: string): Promise<boolean> {
  if (typeof navigator !== "undefined" && typeof navigator.clipboard?.writeText === "function") {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      // Permission refused, or the document was not focused. Try the old way.
    }
  }

  if (typeof document === "undefined") return false;

  const field = document.createElement("textarea");
  field.value = text;
  // readOnly keeps iOS from opening the keyboard; off-screen but not
  // display:none, which would make it unselectable.
  field.readOnly = true;
  field.style.position = "fixed";
  field.style.top = "0";
  field.style.left = "-9999px";
  document.body.appendChild(field);

  try {
    field.select();
    // iOS Safari ignores select() on its own.
    field.setSelectionRange(0, field.value.length);
    return document.execCommand("copy");
  } catch {
    return false;
  } finally {
    field.remove();
  }
}

/// Whether the browser will hand over the camera, the clipboard and the rest.
///
/// Reaching the dashboard on `http://<lan-ip>:7311` is deliberate — it is how a
/// phone at the ground gets to it — so the honest thing is to say which feature
/// the browser is withholding, rather than report it as a permission the person
/// can grant.
export function isSecureContextAvailable(): boolean {
  if (typeof window === "undefined") return true;
  return window.isSecureContext === true;
}
