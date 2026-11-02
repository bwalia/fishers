import type { Metadata } from "next";
import type { ReactNode } from "react";

import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

/// `/hire` is a client component and cannot export metadata, which is the
/// whole reason this file exists — the same reason `c/[slug]` has one.
///
/// Without it the page inherited the root title and description word for
/// word, so `/`, `/hire` and `/docs` reached Google as three pages making an
/// identical claim. Duplicate titles are how a site asks for two of them to
/// be dropped, and the one it keeps is not necessarily the one you wanted.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  const title = `${t("rest.venue_hire")} — ${brand.name}`;
  const description = t("rest.hire_lede");
  return {
    title,
    description,
    // Pinned rather than left to self-canonicalise: this is a page marketing
    // links at, and every `?utm_source=` is otherwise a separate URL claiming
    // the same words.
    alternates: { canonical: "/hire" },
    openGraph: { title, description, url: "/hire", type: "website" },
    twitter: { card: "summary", title, description },
  };
}

export default function HireLayout({ children }: { children: ReactNode }) {
  return children;
}
