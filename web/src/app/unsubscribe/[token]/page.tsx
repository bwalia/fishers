"use client";

import { use, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

type Stage = "ask" | "working" | "off" | "on" | "failed";

/// The link at the bottom of a season email. It works without signing in —
/// the token is the whole permission, and all it can do is this.
///
/// It asks before doing anything. It used to unsubscribe on arrival, and
/// mail security scanners open the links in an email to check them: one that
/// runs the page would have unsubscribed the reader without them ever seeing
/// it. Mail apps' own unsubscribe buttons do not come here at all — they use
/// the one-click POST in the email's List-Unsubscribe header.
export default function UnsubscribePage({ params }: { params: Promise<{ token: string }> }) {
  const t = useT();
  const { token } = use(params);
  const [stage, setStage] = useState<Stage>("ask");

  const set = async (off: boolean) => {
    setStage("working");
    try {
      await api("POST", off ? "/email/season/off" : "/email/season/on", { token });
      setStage(off ? "off" : "on");
    } catch {
      setStage("failed");
    }
  };

  return (
    <main id="main">
      <div className="panel" style={{ maxWidth: 480, margin: "var(--s6) auto" }}>
        {stage === "ask" && (
          <>
            <h1>{t("ss.unsub_ask_title")}</h1>
            <p className="muted">{t("ss.unsub_ask_body")}</p>
            <button className="btn primary" type="button" onClick={() => void set(true)}>
              {t("ss.unsub_button")}
            </button>
          </>
        )}
        {stage === "working" && <div className="skeleton" style={{ height: 72 }} />}
        {stage === "off" && (
          <>
            <h1>{t("ss.unsub_done")}</h1>
            <p className="muted">{t("ss.unsub_body")}</p>
            <button className="btn" type="button" onClick={() => void set(false)}>
              {t("ss.unsub_undo")}
            </button>
          </>
        )}
        {stage === "on" && (
          <div className="empty">
            <Icon name="check" size={28} />
            <h1>{t("ss.resub_done")}</h1>
            <Link className="btn" href="/stats">{t("ss.my_game")}</Link>
          </div>
        )}
        {stage === "failed" && (
          <>
            <h1>{t("rest.that_link_did_not_work")}</h1>
            <p className="muted">{t("ss.unsub_failed")}</p>
          </>
        )}
      </div>
    </main>
  );
}
