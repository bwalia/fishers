import type { Metadata } from "next";
import type { ReactNode } from "react";

type BoardPreview = {
  home_name: string;
  away_name: string;
  club_name?: string | null;
  state?: {
    innings?: Array<{ runs: number; wickets: number; legal_balls: number }>;
    margin?: string | null;
  };
};

/// Server-side only: this runs during the render, never in a browser. In the
/// cluster the API is a Service, so 127.0.0.1 reaches nothing and every shared
/// scoreboard link rendered without its preview.
function apiOrigin() {
  const explicit = process.env.NEXT_PUBLIC_API_BASE?.replace(/\/$/, "");
  if (explicit) return explicit;
  const internal = process.env.API_INTERNAL_BASE?.replace(/\/$/, "");
  if (internal) return internal;
  return `http://127.0.0.1:${process.env.NEXT_PUBLIC_API_PORT || "7312"}`;
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ token: string[] }>;
}): Promise<Metadata> {
  // Catch-all, and a mangled link keeps only its leading hex — as the page does.
  const token = /^[0-9a-f]*/i.exec((await params).token[0] ?? "")?.[0] ?? "";
  const fallback: Metadata = {
    title: "Live scoreboard — Fishers",
    description: "Follow the full live cricket scoreboard. No sign-in required.",
  };
  try {
    const res = await fetch(`${apiOrigin()}/api/v1/public/scoreboard/${token}`, {
      next: { revalidate: 30 },
    });
    if (!res.ok) return fallback;
    const board = (await res.json()) as BoardPreview;
    const inn = board.state?.innings?.at(-1);
    const score = inn
      ? `${inn.runs}/${inn.wickets}`
      : board.state?.margin || "Waiting for first ball";
    const title = `${board.home_name} vs ${board.away_name} — live on Fishers`;
    const description = board.club_name
      ? `${score} · ${board.club_name}`
      : `${score} · live cricket scoreboard`;
    return {
      title,
      description,
      openGraph: { title, description, type: "website" },
      twitter: { card: "summary", title, description },
    };
  } catch {
    return fallback;
  }
}

/// Public share links skip the club dashboard chrome.
export default function LiveLayout({ children }: { children: ReactNode }) {
  return <div className="live-share-root">{children}</div>;
}
