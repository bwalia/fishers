"use client";

import { useCallback, useEffect, useState } from "react";
import { api, readErr, type Invite } from "@/lib/api";
import { Icon } from "@/components/Icon";

/// Invitations waiting for you.
///
/// An invite normally arrives as a link, and a link that got lost in a group
/// chat is the most common reason somebody never joins their club. The invite
/// is already addressed to this account, so it can simply be listed and
/// accepted here — no link needed.
///
/// Renders nothing when there is nothing waiting, so it can sit on any screen.
export function PendingInvites({ onJoined }: { onJoined?: () => void }) {
  const [invites, setInvites] = useState<Invite[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    // Somebody with no invites is the normal case, not an error.
    const mine = await api<Invite[]>("GET", "/invites/mine").catch(() => [] as Invite[]);
    setInvites(mine.filter((i) => i.status === "pending"));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (invites.length === 0) return null;

  const accept = async (invite: Invite) => {
    setBusy(invite.id);
    setError(null);
    try {
      await api("POST", `/invites/${invite.token}/accept`, {});
      await load();
      onJoined?.();
    } catch (err) {
      setError(readErr(err, "Could not accept that invitation"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="panel invites">
      <div className="panel-head">
        <h2>Waiting for you</h2>
        <span className="tag gold">{invites.length}</span>
      </div>
      <p className="muted">
        {invites.length === 1 ? "Somebody has" : "People have"} invited you. Accepting puts
        you straight in.
      </p>
      <ul className="pick-list">
        {invites.map((invite) => (
          <li key={invite.id}>
            <span className="thread-mark" aria-hidden>
              <Icon name={invite.target_type === "event" ? "calendar" : "users"} size={18} />
            </span>
            <div className="pick-who">
              <strong>
                {invite.target_type === "club"
                  ? "A club"
                  : invite.target_type === "team"
                  ? "A team"
                  : "A fixture"}{" "}
                invitation
              </strong>
              <span className="subtle">
                sent{" "}
                {new Date(invite.created_at).toLocaleDateString("en-GB", {
                  day: "numeric",
                  month: "short",
                })}
              </span>
            </div>
            <div className="pick-actions">
              <button
                className="btn primary sm"
                type="button"
                disabled={busy !== null}
                onClick={() => accept(invite)}
              >
                {busy === invite.id ? "Joining…" : "Accept"}
              </button>
            </div>
          </li>
        ))}
      </ul>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
