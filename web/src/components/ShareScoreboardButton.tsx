"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { Icon } from "@/components/Icon";

type ShareResponse = {
  token: string;
  url: string;
  expires_at: string;
};

/// One tap: mint a public live scoreboard link and hand it to WhatsApp, Mail,
/// Messages, or the clipboard. Recipients need no Fishers account.
export function ShareScoreboardButton({
  matchId,
  homeName,
  awayName,
  postToChat = false,
  className,
}: {
  matchId: string;
  homeName: string;
  awayName: string;
  postToChat?: boolean;
  className?: string;
}) {
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const share = async () => {
    setBusy(true);
    setNote(null);
    try {
      const res = await api<ShareResponse>(
        "POST",
        `/cricket/matches/${matchId}/share`,
        { post_to_chat: postToChat, ttl_hours: 48 }
      );
      const title = `${homeName} vs ${awayName} — live scoreboard`;
      const text = `${title}\n${res.url}`;

      if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
        try {
          await navigator.share({ title, text, url: res.url });
          setNote("Shared.");
          return;
        } catch (err) {
          // User dismissed the sheet — fall through to clipboard.
          if (err instanceof DOMException && err.name === "AbortError") {
            setNote("Share cancelled — link still copied.");
          }
        }
      }

      await navigator.clipboard.writeText(res.url);
      setNote("Link copied — paste into WhatsApp, Mail, or Messages.");
    } catch (err) {
      setNote(err instanceof Error ? err.message : "Could not create a share link");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={className ?? "share-scoreboard"}>
      <button type="button" className="btn primary lg" onClick={() => void share()} disabled={busy}>
        <Icon name="share" size={18} />
        {busy ? "Preparing link…" : "Share full scoreboard"}
      </button>
      <p className="muted share-hint">
        Creates a live link anyone can open (WhatsApp, email, Messages). No login needed for
        them. The full scorecard updates every few seconds.
      </p>
      {note && <p className="tag">{note}</p>}
    </div>
  );
}
