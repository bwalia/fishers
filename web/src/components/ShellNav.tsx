"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { clearSession, getStoredUser, type PublicUser } from "@/lib/api";

const links = [
  { href: "/", label: "Overview" },
  { href: "/events", label: "Fixtures" },
  { href: "/shop", label: "Shop" },
  { href: "/stats", label: "Stats" },
  { href: "/clubs", label: "Clubs" },
  { href: "/docs", label: "API docs" },
];

export function ShellNav() {
  const pathname = usePathname();
  const router = useRouter();
  const [user, setUser] = useState<PublicUser | null>(null);

  useEffect(() => {
    setUser(getStoredUser());
  }, [pathname]);

  return (
    <header className="topbar">
      <Link href="/" className="brand">
        Fishers
      </Link>
      <nav className="nav">
        {links.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className={pathname === l.href ? "active" : undefined}
          >
            {l.label}
          </Link>
        ))}
        {user ? (
          <button
            className="btn ghost"
            type="button"
            onClick={() => {
              clearSession();
              setUser(null);
              router.push("/login");
            }}
          >
            Sign out
          </button>
        ) : (
          <Link href="/login">Sign in</Link>
        )}
      </nav>
    </header>
  );
}
