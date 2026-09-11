"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "@/components/Icon";

/// "A player sent me their profile link." Paste it, and you land on their card
/// with this club already chosen — pick the team there and send the invite.
///
/// Accepts the whole message they sent, not just a bare link: people paste
/// "Hi — here's my profile: https://…/p/abc…", and pulling the token out is
/// kinder than asking them to trim it.
export function AddByLink({ clubId }: { clubId: string }) {
  const router = useRouter();
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);

  const go = (e: FormEvent) => {
    e.preventDefault();
    const token = /\/p\/([A-Za-z0-9]{16,64})/.exec(text)?.[1];
    if (!token) {
      setError("That isn't a Fishers profile link — it looks like …/p/ followed by letters and numbers.");
      return;
    }
    router.push(`/p/${token}?club=${encodeURIComponent(clubId)}`);
  };

  return (
    <form className="add-by-link" onSubmit={go}>
      <label htmlFor={`profile-link-${clubId}`}>Got a player&apos;s profile link?</label>
      <div className="add-by-link-row">
        <input
          id={`profile-link-${clubId}`}
          value={text}
          onChange={(e) => {
            setText(e.target.value);
            setError(null);
          }}
          placeholder="Paste the link they sent you"
          autoComplete="off"
        />
        <button className="btn" type="submit" disabled={!text.trim()}>
          <Icon name="link" size={16} /> Open
        </button>
      </div>
      {error && <p className="error">{error}</p>}
    </form>
  );
}
