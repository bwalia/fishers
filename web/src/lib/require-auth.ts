"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getAccessToken } from "@/lib/api";

/// Send signed-out visitors to Sign in, keeping the page they wanted so they
/// land back after. Returns true once a token is present.
export function useRequireAuth(): boolean {
  const router = useRouter();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (getAccessToken()) {
      setReady(true);
      return;
    }
    const next = `${window.location.pathname}${window.location.search}`;
    const safe = next.startsWith("/") && !next.startsWith("//") ? next : "/";
    router.replace(`/login?next=${encodeURIComponent(safe)}`);
  }, [router]);

  return ready;
}
