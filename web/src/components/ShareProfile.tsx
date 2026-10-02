"use client";

import { useState } from "react";
import { api, readErr } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

/// Remembered per device so the getting-started list can tick it off; the
/// link itself works whether or not this is set.
export const sharedKey = (userId: string) => `fishers:profile-shared:${userId}`;

/// A player sends their profile to a club secretary, who invites them in.
///
/// One link, sent however the two of them actually talk — most clubs run on a
/// WhatsApp group, so that goes first. The secretary sees a card with no
/// contact details and sends an invite; the player still has to accept it.
export function ShareProfile({ userId, onShared }: { userId: string; onShared?: () => void }) {
  const t = useT();
  const [link, setLink] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const message = (url: string) =>
    t("fin.share_profile_message", { brand: brand.name, url });

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
      setError(readErr(err, t("le.could_not_make_your_link")));
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
      setError(t("le.could_not_copy_select_the_link_and_cop"));
    }
  };

  const nativeShare = async () => {
    if (!link) return;
    try {
      await navigator.share({ title: t("le.my_brand_profile", { brand: brand.name }), text: message(link), url: link });
      shared();
    } catch {
      /* dismissed the share sheet */
    }
  };

  if (!link) {
    return (
      <div className="share-profile">
        <button className="btn primary" type="button" onClick={getLink} disabled={busy}>
          <Icon name="link" size={16} /> {busy ? t("le.making_your_link") : t("le.get_my_profile_link")}
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
          {t("rest.your_profile_link")}
        </label>
        <input id="profile-link" readOnly value={link} onFocus={(e) => e.target.select()} />
        <button className="btn" type="button" onClick={copy}>
          <Icon name={copied ? "check" : "copy"} size={16} /> {copied ? t("le.copied") : "Copy"}
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
          <Icon name="chat" size={16} /> {t("rest.whatsapp")}
        </a>
        <a
          className="btn"
          href={`mailto:?subject=${encodeURIComponent(`My ${brand.name} player profile`)}&body=${encodeURIComponent(message(link))}`}
          onClick={shared}
        >
          <Icon name="mail" size={16} /> Email
        </a>
        {canNativeShare && (
          <button className="btn" type="button" onClick={nativeShare}>
            <Icon name="share" size={16} /> {t("rest.more")}
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
