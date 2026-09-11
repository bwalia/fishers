"use client";

import { useState } from "react";
import { api, readErr } from "@/lib/api";
import { Icon } from "@/components/Icon";

/// Remembered per device so the getting-started list can tick it off; the
/// link itself works whether or not this is set.
export const sharedKey = (userId: string) => `fishers:profile-shared:${userId}`;

/// A player sends their profile to a club secretary, who invites them in.
///
/// One link, sent however the two of them actually talk — most clubs run on a
/// WhatsApp group, so that goes first. The secretary sees a card with no
/// contact details and sends an invite; the player still has to accept it.
export function ShareProfile({ userId, onShared }: { userId: string; onShared?: () => void }) {
  const [link, setLink] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const message = (url: string) =>
    `Hi — I'd like to play for the club. Here's my Fishers player profile, you can invite me from it: ${url}`;

  const shared = () => {
    try {
      localStorage.setItem(sharedKey(userId), "1");
    } catch {
      /* a private window: the checklist just won't remember */
    }
    onShared?.();
  };

  const getLink = async () => {
    setBusy(true);
    setError(null);
    try {
      const { token } = await api<{ token: string }>("POST", "/me/share-link");
      setLink(`${window.location.origin}/p/${token}`);
    } catch (err) {
      setError(readErr(err, "Could not make your link"));
    } finally {
      setBusy(false);
    }
  };

  const copy = async () => {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
      shared();
    } catch {
      setError("Could not copy — select the link and copy it by hand.");
    }
  };

  const nativeShare = async () => {
    if (!link) return;
    try {
      await navigator.share({ title: "My Fishers profile", text: message(link), url: link });
      shared();
    } catch {
      /* dismissed the share sheet */
    }
  };

  if (!link) {
    return (
      <div className="share-profile">
        <button className="btn primary" type="button" onClick={getLink} disabled={busy}>
          <Icon name="link" size={16} /> {busy ? "Making your link…" : "Get my profile link"}
        </button>
        {error && <p className="error">{error}</p>}
      </div>
    );
  }

  const canNativeShare = typeof navigator !== "undefined" && "share" in navigator;
  return (
    <div className="share-profile">
      <div className="share-link">
        <label className="sr-only" htmlFor="profile-link">
          Your profile link
        </label>
        <input id="profile-link" readOnly value={link} onFocus={(e) => e.target.select()} />
        <button className="btn" type="button" onClick={copy}>
          <Icon name={copied ? "check" : "copy"} size={16} /> {copied ? "Copied" : "Copy"}
        </button>
      </div>
      <div className="share-ways">
        <a
          className="btn"
          href={`https://wa.me/?text=${encodeURIComponent(message(link))}`}
          target="_blank"
          rel="noopener noreferrer"
          onClick={shared}
        >
          <Icon name="chat" size={16} /> WhatsApp
        </a>
        <a
          className="btn"
          href={`mailto:?subject=${encodeURIComponent("My Fishers player profile")}&body=${encodeURIComponent(message(link))}`}
          onClick={shared}
        >
          <Icon name="mail" size={16} /> Email
        </a>
        {canNativeShare && (
          <button className="btn" type="button" onClick={nativeShare}>
            <Icon name="share" size={16} /> More…
          </button>
        )}
      </div>
      <p className="subtle">
        Your secretary sees your name, photo and what you play — not your email or phone. They send an
        invite; you accept it here.
      </p>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
