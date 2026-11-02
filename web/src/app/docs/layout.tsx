import type { Metadata } from "next";
import type { ReactNode } from "react";

import { brand } from "@/brand.generated";
import { getT } from "@/lib/i18n/server";

/// `/docs` is a client component and cannot export metadata. See the note in
/// `hire/layout.tsx`: without this the page served the homepage's title and
/// description verbatim.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getT();
  const title = `${t("rest.api_documentation")} — ${brand.name}`;
  const description = t("rest.docs_description", { brand: brand.name });
  return {
    title,
    description,
    alternates: { canonical: "/docs" },
    openGraph: { title, description, url: "/docs", type: "website" },
    twitter: { card: "summary", title, description },
  };
}

export default function DocsLayout({ children }: { children: ReactNode }) {
  return children;
}
