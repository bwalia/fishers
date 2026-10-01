"use client";

import { useState } from "react";
import { api, readErr } from "@/lib/api";
import { copyText } from "@/lib/clipboard";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

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
  const t = useT();
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  // Kept so the link survives a failed copy. Losing it meant minting another.
  const [link, setLink] = useState<string | null>(null);

  const share = async () => {
    setBusy(true);
    setNote(null);
    setLink(null);
    try {
      const res = await api<ShareResponse>(
        "POST",
        `/cricket/matches/${matchId}/share`,
        { post_to_chat: postToChat, ttl_hours: 48 }
      );
      const title = t("le.home_vs_away_live_scoreboard", { home: homeName, away: awayName });
      setLink(res.url);

      if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
        try {
          // `text` must not contain the link as well. A share target appends
          // `url` to `text`, and the recipient's app then linkifies the two
          // together into one address that resolves to nothing.
          await navigator.share({ title, text: title, url: res.url });
          setNote(t("le.shared"));
          return;
        } catch (err) {
          // User dismissed the sheet — fall through to clipboard.
          if (err instanceof DOMException && err.name === "AbortError") {
            setNote(t("le.share_cancelled_link_still_copied"));
          }
        }
      }

      // Never assume the clipboard is there: it is absent over plain HTTP, which
      // is how this page is reached from a phone at the ground.
      setNote(
        (await copyText(res.url))
          ? t("le.link_copied_paste_into_whatsapp_mail_o")
          : t("le.link_ready_copy_it_below_and_paste_int")
      );
    } catch (err) {
      setNote(readErr(err, t("le.could_not_create_a_share_link")));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={className ?? "share-scoreboard"}>
      <button type="button" className="btn primary lg" onClick={() => void share()} disabled={busy}>
        <Icon name="share" size={18} />
        {busy ? t("le.preparing_link") : t("le.share_full_scoreboard")}
      </button>
      <p className="muted share-hint">
        {t("rest.creates_a_live_link_anyone_can_open_wh")}
      </p>
      {note && <p className="tag">{note}</p>}
      {link && (
        <input
          className="share-link"
          type="text"
          value={link}
          readOnly
          onFocus={(e) => e.currentTarget.select()}
          aria-label={t("rest.live_scoreboard_link")}
        />
      )}
    </div>
  );
}
