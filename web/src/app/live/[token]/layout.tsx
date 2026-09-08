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

function apiOrigin() {
  const explicit = process.env.NEXT_PUBLIC_API_BASE?.replace(/\/$/, "");
  if (explicit) return explicit;
  const port = process.env.NEXT_PUBLIC_API_PORT || "7312";
  return `http://127.0.0.1:${port}`;
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ token: string }>;
}): Promise<Metadata> {
  const { token } = await params;
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
