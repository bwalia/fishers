"use client";

import { useState } from "react";
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
      await navigator.clipboard.writeText(url);
      setNote("Link copied — paste into WhatsApp, Mail, or Messages.");
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
