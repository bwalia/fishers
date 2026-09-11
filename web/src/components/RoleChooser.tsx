"use client";

import { useState } from "react";
import { api, readErr, saveUser, type PublicUser, type RoleIntent } from "@/lib/api";
import { Icon, type IconName } from "@/components/Icon";

const ROLES: { value: RoleIntent; icon: IconName; title: string; body: string }[] = [
  {
    value: "secretary",
    icon: "users",
    title: "I run a club",
    body: "Secretary or organiser. You set up the club, its teams and fixtures, and bring the players in.",
  },
  {
    value: "player",
    icon: "bat",
    title: "I play for a club",
    body: "Set up your player profile, send it to your club's secretary, and accept their invite.",
  },
];

/// The two ways into Fishers look nothing alike — one builds a club, the
/// other joins one — so the first screen asks which, then walks that path.
export function RoleChooser({
  onPicked,
  value,
  compact = false,
}: {
  onPicked: (user: PublicUser | null, role: RoleIntent) => void;
  /// On the signup form: pick locally, save after the account exists.
  value?: RoleIntent | null;
  compact?: boolean;
}) {
  const [busy, setBusy] = useState<RoleIntent | null>(null);
  const [error, setError] = useState<string | null>(null);

  const pick = async (role: RoleIntent) => {
    if (value !== undefined) return onPicked(null, role); // signup: no account yet
    setBusy(role);
    setError(null);
    try {
      const user = await api<PublicUser>("PATCH", "/me", { role_intent: role });
      saveUser(user);
      onPicked(user, role);
    } catch (err) {
      setError(readErr(err, "Could not save that"));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className={`role-chooser${compact ? " compact" : ""}`}>
      <div className="role-options" role="radiogroup" aria-label="How will you use Fishers?">
        {ROLES.map((r) => {
          const selected = value === r.value;
          return (
            <button
              key={r.value}
              type="button"
              role="radio"
              aria-checked={value === undefined ? undefined : selected}
              className={`role-option${selected ? " selected" : ""}`}
              onClick={() => pick(r.value)}
              disabled={busy !== null}
            >
              <span className="role-icon" aria-hidden="true">
                <Icon name={r.icon} size={compact ? 20 : 26} />
              </span>
              <span className="role-text">
                <strong>{busy === r.value ? "Saving…" : r.title}</strong>
                {!compact && <span className="muted">{r.body}</span>}
              </span>
              {selected && (
                <span className="role-tick" aria-hidden="true">
                  <Icon name="check" size={16} />
                </span>
              )}
            </button>
          );
        })}
      </div>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
