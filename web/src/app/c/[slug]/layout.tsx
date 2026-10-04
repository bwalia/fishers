import type { Metadata } from "next";
import type { ReactNode } from "react";

import { apiV1 } from "@/lib/api";
import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

type PublicPage = { club?: { name?: string; tagline?: string | null; about?: string | null } };

/// The one page on this site a search engine has real business ranking, so it
/// is the one page that must not inherit the homepage's title.
///
/// The page itself is a client component and cannot export metadata, which is
/// why this layout exists at all — the same reason `live/[...token]` has one.
export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const t = await getT();
  const canonical = `/c/${slug}`;
  try {
    const res = await fetch(`${apiV1()}/public/clubs/${encodeURIComponent(slug)}`, {
      next: { revalidate: 300 },
    });
    if (!res.ok) return { alternates: { canonical } };
    const club = ((await res.json()) as PublicPage).club;
    const name = club?.name;
    if (!name) return { alternates: { canonical } };

    const title = t("cp.club_on_brand", { club: name, brand: brand.name });
    // The club's own words first. They wrote the tagline to describe
    // themselves, which is exactly what a search result needs.
    const description =
      club.tagline?.trim() ||
      club.about?.trim().slice(0, 180) ||
      t("cp.description", { club: name });
    return {
      title,
      description,
      alternates: { canonical },
      openGraph: { title, description, url: canonical, type: "website" },
      twitter: { card: "summary", title, description },
    };
  } catch {
    // A club page that renders without the API up is still a page; a metadata
    // lookup that throws would make it a 500.
    return { alternates: { canonical } };
  }
}

export default function ClubSiteLayout({ children }: { children: ReactNode }) {
  return children;
}
