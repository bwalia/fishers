"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { api, getAccessToken, type Club, type Invite, type InvitePreview } from "@/lib/api";
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
  // What the link is to, read before anyone signs in, so the page can say
  // "Join Southall Strikers" rather than "You have been invited" to nothing
  // in particular — and say a dead link is dead before anyone signs up for it.
  const [preview, setPreview] = useState<InvitePreview | null>(null);

  useEffect(() => {
    (async () => {
      const seen = await api<InvitePreview>("GET", `/invites/${token}`).catch(() => null);
      setPreview(seen);
      if (seen && !seen.usable) {
        setError(seen.open ? t("jl.link_turned_off") : t("jl.link_already_used"));
        setStage("failed");
        return;
      }
      if (!getAccessToken()) {
        // Nothing to accept with yet. The link is kept so signing in or
        // registering lands them straight back here.
        setStage("signed-out");
        return;
      }
      setStage("joining");
      try {
        const invite = await api<Invite>("POST", `/invites/${token}/accept`);
        const clubId = invite.target_type === "club" ? invite.target_id : seen?.club_id;
        if (clubId) {
          setClub(await api<Club>("GET", `/clubs/${clubId}`).catch(() => null));
        }
        setStage("joined");
      } catch (err) {
        const raw = err instanceof Error ? err.message : "";
        try {
          const body = JSON.parse(raw);
          setError(
            body.code === "removed_from_club"
              ? t("jl.removed_from_club")
              : (body.error ?? t("le.that_invite_could_not_be_used")),
          );
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
            <h1>
              {preview?.club_name
                ? t("jl.join_club", { club: preview.team_name ? `${preview.team_name} · ${preview.club_name}` : preview.club_name })
                : t("rest.you_have_been_invited")}
            </h1>
            {preview?.invited_by_name && !preview.open && (
              <p className="subtle">{t("jl.invited_by", { name: preview.invited_by_name })}</p>
            )}
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
            <h1>{club ? t("rest.you_are_in_club", { club: club.name }) : t("rest.you_are_in")}</h1>
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
              {preview?.open ? t("jl.ask_for_the_current_link") : t("rest.an_invite_can_only_be_used_once_ask_wh")}
            </p>
            <Link className="btn" href="/clubs">{t("rest.your_clubs")}</Link>
          </>
        )}
      </div>
    </main>
  );
}
