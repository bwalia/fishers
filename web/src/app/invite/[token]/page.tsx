"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, getAccessToken, type Club, type Invite } from "@/lib/api";
import { Icon } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

type Stage = "checking" | "signed-out" | "joining" | "joined" | "failed";

export default function InvitePage({ params }: { params: Promise<{ token: string }> }) {
  const t = useT();
  const { token } = use(params);
  const router = useRouter();
  const [stage, setStage] = useState<Stage>("checking");
  const [club, setClub] = useState<Club | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      // Nothing to accept with yet. The link is kept so signing in or
      // registering lands them straight back here.
      setStage("signed-out");
      return;
    }
    setStage("joining");
    (async () => {
      try {
        const invite = await api<Invite>("POST", `/invites/${token}/accept`);
        if (invite.target_type === "club") {
          setClub(await api<Club>("GET", `/clubs/${invite.target_id}`).catch(() => null));
        }
        setStage("joined");
      } catch (err) {
        const raw = err instanceof Error ? err.message : "";
        try {
          setError(JSON.parse(raw).error ?? t("le.that_invite_could_not_be_used"));
        } catch {
          setError(raw || t("le.that_invite_could_not_be_used"));
        }
        setStage("failed");
      }
    })();
  }, [token, t]);

  const next = encodeURIComponent(`/invite/${token}`);

  return (
    <main id="main">
      <div className="panel" style={{ maxWidth: 480, margin: "var(--s6) auto" }}>
        {stage === "checking" && <div className="skeleton" style={{ height: 72 }} />}

        {stage === "signed-out" && (
          <>
            <h1>{t("rest.you_have_been_invited")}</h1>
            <p className="muted">
              {t("rest.sign_in_or_create_an_account_and_you_w")}
            </p>
            <div style={{ display: "flex", gap: "var(--s3)", flexWrap: "wrap" }}>
              <Link className="btn primary" href={`/login?next=${next}`}>Sign in</Link>
              <Link className="btn" href={`/register?next=${next}`}>{t("rest.create_an_account")}</Link>
            </div>
          </>
        )}

        {stage === "joining" && (
          <>
            <h1>{t("rest.joining")}</h1>
            <div className="skeleton" style={{ height: 48 }} />
          </>
        )}

        {stage === "joined" && (
          <div className="empty">
            <Icon name="check" size={28} />
            <h1>You are in{club ? `, ${club.name}` : ""}</h1>
            <button
              className="btn primary"
              type="button"
              onClick={() => router.push(club ? `/clubs/${club.id}` : "/clubs")}
            >
              {t("rest.open_the_club")}
            </button>
          </div>
        )}

        {stage === "failed" && (
          <>
            <h1>{t("rest.that_link_did_not_work")}</h1>
            <p className="error">{error}</p>
            <p className="muted">
              {t("rest.an_invite_can_only_be_used_once_ask_wh")}
            </p>
            <Link className="btn" href="/clubs">Your clubs</Link>
          </>
        )}
      </div>
    </main>
  );
}
