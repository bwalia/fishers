"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { clearSession, getStoredUser, type PublicUser } from "@/lib/api";
import { Icon, type IconName } from "@/components/Icon";

const links: { href: string; label: string; icon: IconName }[] = [
  { href: "/", label: "Overview", icon: "home" },
  { href: "/events", label: "Fixtures", icon: "calendar" },
  { href: "/score", label: "Score", icon: "bat" },
  { href: "/stats", label: "Stats", icon: "chart" },
  { href: "/shop", label: "Shop", icon: "shop" },
  { href: "/clubs", label: "Clubs", icon: "users" },
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
        <Icon name="ball" size={22} />
        Fishers
      </Link>
      <nav className="nav" aria-label="Main">
        {links.map((l) => {
          const active = l.href === "/" ? pathname === "/" : pathname.startsWith(l.href);
          return (
            <Link
              key={l.href}
              href={l.href}
              className={active ? "active" : undefined}
              aria-current={active ? "page" : undefined}
            >
              <Icon name={l.icon} size={16} />
              {l.label}
            </Link>
          );
        })}
        {user ? (
          <button
            type="button"
            onClick={() => {
              clearSession();
              setUser(null);
              router.push("/login");
            }}
          >
            <Icon name="signOut" size={16} />
            Sign out
          </button>
        ) : (
          <>
            <Link href="/login">
              <Icon name="signIn" size={16} />
              Sign in
            </Link>
            <Link href="/register" className="active">
              Join
            </Link>
          </>
        )}
      </nav>
    </header>
  );
}
