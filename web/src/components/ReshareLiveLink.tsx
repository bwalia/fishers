"use client";

import { useState } from "react";
import { copyText } from "@/lib/clipboard";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

/// Recipients of a live link can pass it on again without signing in.
export function ReshareLiveLink({
  homeName,
  awayName,
}: {
  homeName: string;
  awayName: string;
}) {
  const t = useT();
  const [note, setNote] = useState<string | null>(null);

  const share = async () => {
    const url = window.location.href;
    const title = `${homeName} vs ${awayName} — live scoreboard`;
    setNote(null);
    try {
      if (typeof navigator.share === "function") {
        try {
          // `text` must not contain the link as well. A share target appends
          // `url` to `text`, and the recipient's app then linkifies the two
          // together into one address that resolves to nothing.
          await navigator.share({ title, text: title, url });
          setNote(t("le.shared"));
          return;
        } catch (err) {
          if (err instanceof DOMException && err.name === "AbortError") {
            setNote(t("le.share_cancelled"));
            return;
          }
        }
      }
      // The clipboard is absent over plain HTTP; the address bar still has the
      // link, so say that rather than failing on a page they are already on.
      setNote(
        (await copyText(url))
          ? t("le.link_copied_paste_into_whatsapp_mail_o")
          : t("le.copy_this_page_s_address_from_the_addr")
      );
    } catch (err) {
      setNote(err instanceof Error ? err.message : t("le.could_not_share"));
    }
  };

  return (
    <div className="share-scoreboard">
      <button type="button" className="btn primary" onClick={() => void share()}>
        <Icon name="share" size={16} />
        {t("rest.share_this_scoreboard")}
      </button>
      <p className="muted share-hint">{t("rest.forward_to_whatsapp_email_or_messages")}</p>
      {note && <p className="tag">{note}</p>}
    </div>
  );
}
