"use client";

import { useEffect, useState } from "react";
import { api, SPORTS } from "./api";

type OfferedSports = { offered?: string[]; all?: string[] };

/// Asked once per page load and shared between every picker.
///
/// Six components ask the same question and the answer cannot differ between
/// them, so six requests would be six round trips for one fact that changes
/// only when the deployment is redeployed.
let pending: Promise<readonly string[]> | null = null;

function offeredSports(): Promise<readonly string[]> {
  pending ??= api<OfferedSports>("GET", "/sports", undefined, false)
    .then((answer) => (answer.offered?.length ? answer.offered : SPORTS))
    .catch(() => {
      // The API is the authority here and it did not answer. Falling back to
      // the whole list is what every picker did before the endpoint existed,
      // and the server refuses a sport it does not offer regardless — so the
      // worst case is a refusal that names the sport, not a picker nobody can
      // use. Clearing `pending` lets the next picker try again rather than
      // caching one bad moment for the rest of the session.
      pending = null;
      return SPORTS;
    });
  return pending;
}

/// Which sports a picker should offer.
///
/// Starts as the whole list rather than empty: a picker with nothing in it is
/// a dead end, and this resolves in one same-origin request. Deliberately not
/// the other way round — an empty picker while the answer is in flight is the
/// worse of the two failures.
///
/// This is what a picker *offers*. What a label may *say* is a different
/// question and stays `SPORTS`, because a club that already plays football has
/// to render with a name and a badge on a cricket-only deployment.
export function useOfferedSports(): readonly string[] {
  const [sports, setSports] = useState<readonly string[]>(SPORTS);
  useEffect(() => {
    let live = true;
    void offeredSports().then((answer) => {
      if (live) setSports(answer);
    });
    return () => {
      live = false;
    };
  }, []);
  return sports;
}
