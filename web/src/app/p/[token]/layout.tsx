import type { Metadata } from "next";
import type { ReactNode } from "react";

/// Given out, never found. A pay link shows a club's bank details and a
/// profile link a player's card: neither belongs in a search index (robots.ts
/// already asks crawlers to stay out of `/p/`; this covers a crawler that
/// arrives from a link anyway), and neither token should leave in a Referer
/// header when somebody taps out of the page.
export const metadata: Metadata = {
  robots: { index: false, follow: false, nocache: true, googleBot: { index: false, follow: false } },
  referrer: "no-referrer",
};

export default function SharedLinkLayout({ children }: { children: ReactNode }) {
  return children;
}
