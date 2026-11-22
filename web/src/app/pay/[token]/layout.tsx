import type { Metadata } from "next";
import type { ReactNode } from "react";

/// Given out, never found: a pay link shows a club's bank details, so it
/// stays out of search indexes, and its token never leaves in a Referer
/// header when somebody taps out of the page.
export const metadata: Metadata = {
  robots: { index: false, follow: false, nocache: true, googleBot: { index: false, follow: false } },
  referrer: "no-referrer",
};

export default function PayLinkLayout({ children }: { children: ReactNode }) {
  return children;
}
