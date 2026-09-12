"use client";

import Link from "next/link";
import { use, useEffect, useState } from "react";
import { api, getAccessToken, readErr, type Club, type OpponentIdentity } from "@/lib/api";
import { Icon } from "@/components/Icon";

/// Where a club's or a team's code lands — the link printed under its QR on
/// the club page, which an opposition captain is sent or scans at the ground.
///
/// It says who the code belongs to and offers the one thing to do with it:
/// start a match against them. (Before this page the link was a 404.)
export default function PlayPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [who, setWho] = useState<OpponentIdentity | null>(null);
  /// Their own club's code: you cannot play yourself, so it is offered as
  /// something to send rather than something to play against.
  const [ours, setOurs] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      window.location.href = `/login?next=${encodeURIComponent(`/play/${token}`)}`;
      return;
    }
    (async () => {
      try {
        const found = await api<OpponentIdentity>("POST", "/opponents/lookup", { token });
        setWho(found);
        const mine = await api<Club[]>("GET", "/clubs").catch(() => [] as Club[]);
        setOurs(mine.some((c) => c.id === found.club_id));
      } catch (err) {
        setError(readErr(err, "That code is not one of ours"));
      }
    })();
  }, [token]);

  return (
    <main id="main" className="shared-profile">
      {error ? (
        <div className="panel empty">
          <Icon name="link" size={28} />
          <h1>This code didn&apos;t work</h1>
          <p className="muted">{error}. Ask them to send their link again.</p>
        </div>
      ) : !who ? (
        <div className="panel">
          <div className="skeleton" style={{ height: 120 }} />
        </div>
      ) : (
        <div className="panel play-card">
          <span className="tag grey">{who.kind === "team" ? `A team at ${who.club_name}` : "A club on Fishers"}</span>
          <h1>{who.name}</h1>
          {ours ? (
            <>
              <p className="muted">
                This is your own code. Send this link to the opposition&apos;s captain — it puts them
                straight into a match against you, and they can agree the terms and name their eleven
                from their phone.
              </p>
              <Link className="btn" href="/clubs">
                <Icon name="users" size={16} /> Back to your club
              </Link>
            </>
          ) : (
            <>
              <p className="muted">
                Start a match against them and their captain can agree the terms and name their own
                eleven from their phone.
              </p>
              <Link className="btn primary lg" href={`/score?against=${encodeURIComponent(token)}`}>
                <Icon name="bat" size={16} /> Start a match against {who.name}
              </Link>
            </>
          )}
        </div>
      )}
    </main>
  );
}
