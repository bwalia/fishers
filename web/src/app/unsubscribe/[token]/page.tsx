"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

type Stage = "working" | "off" | "on" | "failed";

/// The link at the bottom of a season email. It works without signing in —
/// the token is the whole permission, and all it can do is this — and it
/// does what it says on arrival rather than asking a second time. Turning
/// them back on is one button, because people tap these by accident.
export default function UnsubscribePage({ params }: { params: Promise<{ token: string }> }) {
  const t = useT();
  const { token } = use(params);
  const [stage, setStage] = useState<Stage>("working");

  const set = async (off: boolean) => {
    setStage("working");
    try {
      await api("POST", off ? "/email/season/off" : "/email/season/on", { token });
      setStage(off ? "off" : "on");
    } catch {
      setStage("failed");
    }
  };

  useEffect(() => {
    void set(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  return (
    <main id="main">
      <div className="panel" style={{ maxWidth: 480, margin: "var(--s6) auto" }}>
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
