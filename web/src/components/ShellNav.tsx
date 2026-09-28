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
import { brand } from "@/brand.generated";

type NavLink = { href: string; label: string; icon: IconName };

/// The bar, in the order somebody uses it.
///
/// Twelve flat links filled the whole width and said nothing about what
/// belonged with what — every destination shouting at the same volume is the
/// same as none of them shouting. These three stay in the bar because they are
/// opened daily; Chats also carries the unread badge, and a badge inside a
/// closed menu is a badge nobody sees.
const primary: NavLink[] = [
  { href: "/", label: "Overview", icon: "home" },
  { href: "/events", label: "Fixtures", icon: "calendar" },
  { href: "/chat", label: "Chats", icon: "chat" },
];

/// The rest, in two groups somebody can name without being told.
///
/// "Play" is the things around a match — whether you can, scoring it, the
/// competition it belongs to. "Club" is the club itself: who is in it, how it
/// has done, its ground and its kit.
const groups: { label: string; icon: IconName; links: NavLink[] }[] = [
  {
    label: "Play",
    icon: "bat",
    links: [
      { href: "/availability", label: "Availability", icon: "clock" },
      { href: "/score", label: "Score", icon: "bat" },
      { href: "/tournaments", label: "Tournaments", icon: "trophy" },
    ],
  },
  {
    label: "Club",
    icon: "users",
    links: [
      { href: "/clubs", label: "Clubs", icon: "users" },
      { href: "/stats", label: "Stats", icon: "chart" },
      { href: "/hire", label: "Hire", icon: "pin" },
      { href: "/shop", label: "Shop", icon: "shop" },
    ],
  },
];

/// Only for whoever runs the service, and set apart from the everyday links
/// rather than queued behind them: it is a different kind of thing, not the
/// thirteenth of the same kind. The page checks for itself — this only decides
/// whether the link is drawn.
const adminLink: NavLink = { href: "/admin", label: "System", icon: "shield" };

export function ShellNav() {
  const pathname = usePathname();
  const router = useRouter();
  const [user, setUser] = useState<PublicUser | null>(null);
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    setUser(getStoredUser());
    setChecked(true);
  }, [pathname]);

  // Signed out on the landing page, the app's ten links would each end at a
  // sign-in screen; the page itself says what is behind them.
  const landing = pathname === "/" && checked && !user;

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));

  // The stored copy of /me carries the flag. Hiding the link is courtesy, not
  // security: the endpoints check for themselves and answer 404 to anybody
  // else, so a stale cached `true` shows a link that leads nowhere rather than
  // a page that shows anything.
  const isAdmin = !!user?.platform_admin;

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
        {brand.name}
      </Link>
      {!landing && <>
      <nav className="nav" aria-label="Main">
        {primary.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className={isActive(l.href) ? "active" : undefined}
            aria-current={isActive(l.href) ? "page" : undefined}
          >
            <Icon name={l.icon} size={16} />
            {l.label}
            {user && l.href === "/chat" && <ChatBadge />}
          </Link>
        ))}
      </nav>

      {/* Outside .nav for the same reason as the bell below: .nav scrolls
          sideways on a narrow screen, and a scrolling ancestor clips an
          absolutely-positioned panel. */}
      <div className="nav-groups">
        {groups.map((group) => (
          <OverflowMenu
            key={group.label}
            label={group.label}
            icon={group.icon}
            showLabel
            chevron
            className={`nav-group${group.links.some((l) => isActive(l.href)) ? " active" : ""}`}
          >
            {group.links.map((l) => (
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
        ))}
      </div>
      </>}

      {/* Outside the nav on purpose. `.nav` scrolls sideways on a narrow
          screen, and an ancestor that scrolls clips an absolutely-positioned
          dropdown — the bell opened, and its panel was cut off where nobody
          could see it. Actions that own a popover live in their own group. */}
      <div className="nav-actions">
        {/* Set apart by a rule, not queued behind the everyday links: running
            the service is a different kind of thing from playing for a club. */}
        {user && isAdmin && (
          <Link
            href={adminLink.href}
            className={`nav-admin${isActive(adminLink.href) ? " active" : ""}`}
            aria-current={isActive(adminLink.href) ? "page" : undefined}
          >
            <Icon name={adminLink.icon} size={16} />
            {adminLink.label}
          </Link>
        )}
        <ThemeToggle />
        {user && <NotificationBell />}
        {user ? (
          // Profile and Sign out together, on the right, which is where people
          // look for both. It also puts the one destructive action out of the
          // row of navigation, rather than one tab away from Clubs.
          <OverflowMenu
            label={user.name.split(" ")[0] || "You"}
            icon="book"
            showLabel
            chevron
            className={`nav-you${isActive("/profile") ? " active" : ""}`}
          >
            <Link
              href="/profile"
              role="menuitem"
              className="overflow-item"
              aria-current={isActive("/profile") ? "page" : undefined}
            >
              <Icon name="book" size={16} />
              Profile
            </Link>
            <button
              type="button"
              role="menuitem"
              className="overflow-item"
              onClick={() => {
                clearSession();
                setUser(null);
                router.push("/login");
              }}
            >
              <Icon name="signOut" size={16} />
              Sign out
            </button>
          </OverflowMenu>
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
