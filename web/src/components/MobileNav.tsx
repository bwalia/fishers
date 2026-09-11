"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { Icon, type IconName } from "@/components/Icon";
import { ChatBadge } from "@/components/ChatBadge";

/// The four places somebody goes on a phone, and everything else behind More.
///
/// The top bar's horizontal scroller could not carry ten links: squeezed
/// between the brand and the actions it collapsed to 37px, showing two of
/// them. A bottom bar is what a thumb reaches and what every other app on the
/// phone does, and four plus More is the shape Apple and Material both
/// recommend.
const PRIMARY: { href: string; label: string; icon: IconName }[] = [
  { href: "/", label: "Home", icon: "home" },
  { href: "/events", label: "Fixtures", icon: "calendar" },
  { href: "/score", label: "Score", icon: "bat" },
  { href: "/chat", label: "Chats", icon: "chat" },
];

/// Everything the bottom bar has no room for. Ordered by how often a club
/// actually opens them, not alphabetically.
const MORE: { href: string; label: string; icon: IconName }[] = [
  { href: "/availability", label: "Availability", icon: "clock" },
  { href: "/clubs", label: "Clubs", icon: "users" },
  { href: "/profile", label: "Profile", icon: "book" },
  { href: "/notifications", label: "Notifications", icon: "inbox" },
  { href: "/stats", label: "Stats", icon: "chart" },
  { href: "/tournaments", label: "Tournaments", icon: "trophy" },
  { href: "/shop", label: "Shop", icon: "shop" },
];

export function MobileNav() {
  const pathname = usePathname();
  const [more, setMore] = useState(false);

  // A tap that navigates should close the sheet behind it.
  useEffect(() => setMore(false), [pathname]);

  // Public pages are not the app; somebody arriving from a shared link is not
  // a member and a tab bar would only offer them things to be refused from.
  if (pathname.startsWith("/live/") || pathname.startsWith("/c/")) return null;

  const active = (href: string) =>
    href === "/" ? pathname === "/" : pathname.startsWith(href);
  const moreActive = MORE.some((m) => active(m.href));

  return (
    <>
      {more && (
        <div className="more-sheet" role="dialog" aria-label="More">
          <div className="more-grid">
            {MORE.map((m) => (
              <Link
                key={m.href}
                href={m.href}
                className={active(m.href) ? "more-item on" : "more-item"}
              >
                <Icon name={m.icon} size={22} />
                {m.label}
              </Link>
            ))}
          </div>
        </div>
      )}
      {/* Sits above the sheet so the same button closes it. */}
      <nav className="tabbar" aria-label="Main">
        {PRIMARY.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className={active(l.href) && !more ? "on" : undefined}
            aria-current={active(l.href) ? "page" : undefined}
          >
            <Icon name={l.icon} size={22} />
            {l.label}
            {l.href === "/chat" && <ChatBadge />}
          </Link>
        ))}
        <button
          type="button"
          className={more || moreActive ? "on" : undefined}
          aria-expanded={more}
          onClick={() => setMore((o) => !o)}
        >
          <Icon name="more" size={22} />
          More
        </button>
      </nav>
    </>
  );
}
