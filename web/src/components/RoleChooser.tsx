"use client";

import { useState } from "react";
import { api, readErr, saveUser, type PublicUser, type RoleIntent } from "@/lib/api";
import { Icon, type IconName } from "@/components/Icon";
import { brand } from "@/brand.generated";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n";

const ROLES: { value: RoleIntent; icon: IconName; title: Key; body: Key }[] = [
  {
    value: "secretary",
    icon: "users",
    title: "le.i_run_a_club",
    body: "le.secretary_or_organiser_you_set_up_the",
  },
  {
    value: "player",
    icon: "bat",
    title: "le.i_play_for_a_club",
    body: "le.set_up_your_player_profile_send_it_to",
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
  const t = useT();
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
      setError(readErr(err, t("le.could_not_save_that")));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className={`role-chooser${compact ? " compact" : ""}`}>
      <div className="role-options" role="radiogroup" aria-label={t("fin.how_will_you_use", { brand: brand.name })}>
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
                <strong>{busy === r.value ? t("la.saving") : t(r.title)}</strong>
                {!compact && <span className="muted">{t(r.body)}</span>}
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
