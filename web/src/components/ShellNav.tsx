"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { clearSession, getStoredUser, type PublicUser } from "@/lib/api";
import { BrandMark } from "@/components/BrandMark";
import { Icon, type IconName } from "@/components/Icon";
import { NotificationBell } from "@/components/NotificationBell";
import { OverflowMenu } from "@/components/OverflowMenu";
import { ChatBadge } from "@/components/ChatBadge";
import { ThemeToggle } from "@/components/ThemeToggle";

const links: { href: string; label: string; icon: IconName }[] = [
  { href: "/", label: "Overview", icon: "home" },
  { href: "/events", label: "Fixtures", icon: "calendar" },
  { href: "/chat", label: "Chats", icon: "chat" },
  { href: "/availability", label: "Availability", icon: "clock" },
  { href: "/score", label: "Score", icon: "bat" },
  { href: "/tournaments", label: "Tournaments", icon: "trophy" },
  { href: "/stats", label: "Stats", icon: "chart" },
  { href: "/shop", label: "Shop", icon: "shop" },
  { href: "/clubs", label: "Clubs", icon: "users" },
  { href: "/profile", label: "Profile", icon: "book" },
];

/// The row needs ~1034px. Below that the last of these went off the end — at
/// 1366 Profile, at 1280 Clubs too, on an iPad half the bar — reachable only
/// by a sideways scroll nobody knew was there. Under 1440 they move into More;
/// the first five, the everyday ones, always stay in the bar.
const PRIMARY = 5;

export function ShellNav() {
  const pathname = usePathname();
  const router = useRouter();
  const [user, setUser] = useState<PublicUser | null>(null);

  useEffect(() => {
    setUser(getStoredUser());
  }, [pathname]);

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));

  // A public board or a club's own page is not the app: somebody arrives
  // there from a search result or a shared link, and the club chrome would
  // only ask them to sign in to something they are not part of.
  if (pathname.startsWith("/live/") || pathname.startsWith("/c/")) {
    return null;
  }

  return (
    <header className="topbar">
      {/* The bar itself is full width so it reads as the edge of the app;
          this inner track keeps its contents on the same grid as the page. */}
      <div className="topbar-inner">
      <Link href="/" className="brand">
        <BrandMark size={24} />
        Fishers
      </Link>
      <nav className="nav" aria-label="Main">
        {links.map((l, i) => {
          const active = isActive(l.href);
          const cls = [active && "active", i >= PRIMARY && "nav-extra"].filter(Boolean).join(" ");
          return (
            <Link
              key={l.href}
              href={l.href}
              className={cls || undefined}
              aria-current={active ? "page" : undefined}
            >
              <Icon name={l.icon} size={16} />
              {l.label}
              {user && l.href === "/chat" && <ChatBadge />}
            </Link>
          );
        })}
      </nav>

      {/* Outside .nav for the same reason as the bell below: .nav scrolls,
          and a scrolling ancestor would clip the menu. */}
      <OverflowMenu
        label="More"
        showLabel
        className={`nav-more${links.slice(PRIMARY).some((l) => isActive(l.href)) ? " active" : ""}`}
      >
        {links.slice(PRIMARY).map((l) => (
          <Link
            key={l.href}
            href={l.href}
            role="menuitem"
            className="overflow-item"
            aria-current={isActive(l.href) ? "page" : undefined}
          >
            <Icon name={l.icon} size={16} />
            {l.label}
          </Link>
        ))}
      </OverflowMenu>

      {/* Outside the nav on purpose. `.nav` scrolls sideways on a narrow
          screen, and an ancestor that scrolls clips an absolutely-positioned
          dropdown — the bell opened, and its panel was cut off where nobody
          could see it. Actions that own a popover live in their own group. */}
      <div className="nav-actions">
        <ThemeToggle />
        {user && <NotificationBell />}
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
      </div>
      </div>
    </header>
  );
}
