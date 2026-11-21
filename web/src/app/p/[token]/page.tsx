"use client";

import { use } from "react";
import { isProfileToken } from "@/lib/pay-link";
import { PayLinkPage } from "@/components/PayLinkPage";
import { SharedProfile } from "@/components/SharedProfile";

/// `/p/<token>` is two kinds of link: a player's profile, shared with a club
/// secretary, and a bill's pay link, posted in the club's WhatsApp group. The
/// token's shape says which (see `isProfileToken`), and the two pages share
/// nothing else — a profile needs a signed-in secretary; a pay link must
/// never ask anybody to sign in.
export default function SharedLinkPage({ params }: { params: Promise<{ token: string }> }) {
  const { token: raw } = use(params);
  const token = safeDecode(raw);
  return isProfileToken(token) ? <SharedProfile token={token} /> : <PayLinkPage token={token} />;
}

function safeDecode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}
