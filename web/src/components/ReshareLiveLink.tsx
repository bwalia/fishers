"use client";

import { useState } from "react";
import { copyText } from "@/lib/clipboard";
import { Icon } from "@/components/Icon";

/// Recipients of a live link can pass it on again without signing in.
export function ReshareLiveLink({
  homeName,
  awayName,
}: {
  homeName: string;
  awayName: string;
}) {
  const [note, setNote] = useState<string | null>(null);

  const share = async () => {
    const url = window.location.href;
    const title = `${homeName} vs ${awayName} — live scoreboard`;
    const text = `${title}\n${url}`;
    setNote(null);
    try {
      if (typeof navigator.share === "function") {
        try {
          await navigator.share({ title, text, url });
          setNote("Shared.");
          return;
        } catch (err) {
          if (err instanceof DOMException && err.name === "AbortError") {
            setNote("Share cancelled.");
            return;
          }
        }
      }
      // The clipboard is absent over plain HTTP; the address bar still has the
      // link, so say that rather than failing on a page they are already on.
      setNote(
        (await copyText(url))
          ? "Link copied — paste into WhatsApp, Mail, or Messages."
          : "Copy this page's address from the address bar to share it."
      );
    } catch (err) {
      setNote(err instanceof Error ? err.message : "Could not share");
    }
  };

  return (
    <div className="share-scoreboard">
      <button type="button" className="btn primary" onClick={() => void share()}>
        <Icon name="share" size={16} />
        Share this scoreboard
      </button>
      <p className="muted share-hint">Forward to WhatsApp, email, or Messages in one tap.</p>
      {note && <p className="tag">{note}</p>}
    </div>
  );
}
