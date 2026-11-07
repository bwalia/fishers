"use client";

import { useCallback, useEffect, useState } from "react";
import { api, type Invite } from "@/lib/api";
import { copyText } from "@/lib/clipboard";
import { Icon } from "@/components/Icon";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";

/// One link for the whole squad.
///
/// An invite to a person is spent by the first one through it: right for
/// "Invite instead" on one email, and wrong for the link a secretary drops
/// into the team WhatsApp group, where the first player in used it up and
/// every other player was told it had already been used. This one is
/// addressed to nobody, is never used up, and opens the club for whoever
/// follows it, until the secretary turns it off.
export function ClubJoinLink({ clubId, clubName }: { clubId: string; clubName: string }) {
  const t = useT();
  const [link, setLink] = useState<Invite | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setLink(await api<Invite | null>("GET", `/clubs/${clubId}/join-link`));
    } catch {
      setLink(null);
    } finally {
      setLoaded(true);
    }
  }, [clubId]);

  useEffect(() => {
    void load();
  }, [load]);

  const make = async (fresh: boolean) => {
    if (fresh && !confirm(t("jl.confirm_new_link"))) return;
    setBusy(true);
    setNote(null);
    try {
      setLink(await api<Invite>("POST", `/clubs/${clubId}/join-link`, { fresh }));
      if (fresh) setNote(t("jl.new_link_made"));
    } catch {
      setNote(t("jl.could_not_make_link"));
    } finally {
      setBusy(false);
    }
  };

  const stop = async () => {
    if (!confirm(t("jl.confirm_turn_off"))) return;
    setBusy(true);
    setNote(null);
    try {
      await api("DELETE", `/clubs/${clubId}/join-link`);
      setLink(null);
      setNote(t("jl.turned_off"));
    } catch {
      setNote(t("jl.could_not_turn_off"));
    } finally {
      setBusy(false);
    }
  };

  if (!loaded) return null;

  const url = link ? `${window.location.origin}/invite/${link.token}` : null;
  const message = url ? t("jl.whatsapp_message", { club: clubName, brand: brand.name, url }) : "";

  return (
    <div className="add-member club-join-link" id="join-link">
      <h3 style={{ marginBottom: 4 }}>
        <Icon name="link" size={16} /> {t("jl.title")}
      </h3>
      <p className="subtle">{t("jl.explainer")}</p>

      {!url && (
        <button className="btn primary" type="button" disabled={busy} onClick={() => void make(false)}>
          <Icon name="link" size={16} /> {t("jl.make_link")}
        </button>
      )}

      {url && link && (
        <>
          <div className="invite-link">
            <code data-testid="club-join-link">{url}</code>
            <button className="btn sm" type="button" onClick={() => void copyText(url)}>
              <Icon name="copy" size={14} /> {t("cl.copy")}
            </button>
          </div>
          <div style={{ display: "flex", gap: "var(--s2)", flexWrap: "wrap", marginTop: 8 }}>
            <a
              className="btn sm primary"
              href={`https://wa.me/?text=${encodeURIComponent(message)}`}
              target="_blank"
              rel="noopener noreferrer"
            >
              <Icon name="chat" size={14} /> {t("rest.whatsapp")}
            </a>
            <button className="btn sm" type="button" disabled={busy} onClick={() => void make(true)}>
              {t("jl.new_link")}
            </button>
            <button className="btn sm ghost" type="button" disabled={busy} onClick={() => void stop()}>
              {t("jl.turn_off")}
            </button>
          </div>
          <p className="subtle" style={{ marginTop: 8 }}>
            {t("jl.joined_through_it", { count: link.uses ?? 0, n: link.uses ?? 0 })}
          </p>
        </>
      )}
      {note && <p className="muted">{note}</p>}
    </div>
  );
}
