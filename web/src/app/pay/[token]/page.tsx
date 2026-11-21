"use client";

import { use } from "react";
import { PayLinkPage } from "@/components/PayLinkPage";

/// A bill's pay link, posted in the club's WhatsApp group: `/pay/<token>`.
/// Its own path, so it never has to be told apart from a profile link by the
/// token's shape. (`/p/<token>` still opens pay links made before it moved.)
export default function PayLinkRoute({ params }: { params: Promise<{ token: string }> }) {
  const { token: raw } = use(params);
  let token = raw;
  try {
    token = decodeURIComponent(raw);
  } catch {
    /* a malformed escape lands on the "this link isn't right" page */
  }
  return <PayLinkPage token={token} />;
}
