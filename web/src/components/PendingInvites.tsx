"use client";

import { useCallback, useEffect, useState } from "react";
import { api, errCode, readErr, type Invite } from "@/lib/api";
import { Icon } from "@/components/Icon";

/// Invitations waiting for you.
///
/// An invite normally arrives as a link, and a link that got lost in a group
/// chat is the most common reason somebody never joins their club. The invite
/// is already addressed to this account, so it can simply be listed and
/// accepted here — no link needed.
///
/// Renders nothing when there is nothing waiting, so it can sit on any screen.
export function PendingInvites({
  onJoined,
  onCount,
}: {
  onJoined?: () => void;
  /// For the getting-started guide, which ticks "send your profile" off once
  /// an invite has come back.
  onCount?: (n: number) => void;
}) {
  const [invites, setInvites] = useState<Invite[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    // Somebody with no invites is the normal case, not an error.
    const mine = await api<Invite[]>("GET", "/invites/mine").catch(() => [] as Invite[]);
    const pending = mine.filter((i) => i.status === "pending");
    setInvites(pending);
    onCount?.(pending.length);
  }, [onCount]);

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
      // The fix is on this same page, in the getting-started guide.
      setError(
        errCode(err) === "unverified"
          ? "Confirm your email or phone number first — the code is in the getting-started steps below."
          : readErr(err, "Could not accept that invitation")
      );
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="panel invites" id="pending-invites">
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
                {invite.target_name ??
                  `A ${invite.target_type === "event" ? "fixture" : invite.target_type} invitation`}
              </strong>
              <span className="subtle">
                {invite.invited_by_name ? `from ${invite.invited_by_name} · ` : ""}sent{" "}
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
