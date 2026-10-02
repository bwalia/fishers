"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { Icon, type IconName } from "@/components/Icon";
import { ChatBadge } from "@/components/ChatBadge";
import { getStoredUser } from "@/lib/api";
import { useT } from "@/lib/i18n/provider";
import type { Key } from "@/lib/i18n/en";

/// The four places somebody goes on a phone, and everything else behind More.
///
/// The top bar's horizontal scroller could not carry ten links: squeezed
/// between the brand and the actions it collapsed to 37px, showing two of
/// them. A bottom bar is what a thumb reaches and what every other app on the
/// phone does, and four plus More is the shape Apple and Material both
/// recommend.
// `label` is a dictionary key: the bar is built once, read in whichever
// language the viewer chose.
const PRIMARY: { href: string; label: Key; icon: IconName }[] = [
  { href: "/", label: "nav.home", icon: "home" },
  { href: "/events", label: "nav.fixtures", icon: "calendar" },
  { href: "/score", label: "nav.score", icon: "bat" },
  { href: "/chat", label: "nav.chats", icon: "chat" },
];

/// Everything the bottom bar has no room for. Ordered by how often a club
/// actually opens them, not alphabetically.
const MORE: { href: string; label: Key; icon: IconName }[] = [
  { href: "/availability", label: "nav.availability", icon: "clock" },
  { href: "/clubs", label: "nav.clubs", icon: "users" },
  { href: "/scores", label: "nav.world_scores", icon: "ball" },
  { href: "/profile", label: "nav.profile", icon: "book" },
  { href: "/notifications", label: "nav.notifications", icon: "inbox" },
  { href: "/stats", label: "nav.stats", icon: "chart" },
  { href: "/tournaments", label: "nav.tournaments", icon: "trophy" },
  { href: "/shop", label: "nav.shop", icon: "shop" },
  { href: "/hire", label: "nav.hire", icon: "pin" },
];

export function MobileNav() {
  const t = useT();
  const pathname = usePathname();
  const [more, setMore] = useState(false);
  // Signed-out visitors on the landing page get the page, not the app's tabs.
  const [signedOut, setSignedOut] = useState(false);
  useEffect(() => setSignedOut(!getStoredUser()), [pathname]);

  // A tap that navigates should close the sheet behind it.
  useEffect(() => setMore(false), [pathname]);

  // Public pages are not the app; somebody arriving from a shared link is not
  // a member and a tab bar would only offer them things to be refused from.
  if (pathname.startsWith("/live/") || pathname.startsWith("/c/")) return null;
  // Marketing and auth screens are not the app shell.
  if (signedOut && (pathname === "/" || pathname === "/login" || pathname === "/register" || pathname === "/welcome" || pathname === "/docs" || pathname === "/privacy")) {
    return null;
  }

  const active = (href: string) =>
    href === "/" ? pathname === "/" : pathname.startsWith(href);
  const moreActive = MORE.some((m) => active(m.href));

  return (
    <>
      {more && (
        <div className="more-sheet" role="dialog" aria-label={t("nav.more")}>
          <div className="more-grid">
            {MORE.map((m) => (
              <Link
                key={m.href}
                href={m.href}
                className={active(m.href) ? "more-item on" : "more-item"}
              >
                <Icon name={m.icon} size={22} />
                {t(m.label)}
              </Link>
            ))}
          </div>
        </div>
      )}
      {/* Sits above the sheet so the same button closes it. */}
      <nav className="tabbar" aria-label={t("nav.main")}>
        {PRIMARY.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className={active(l.href) && !more ? "on" : undefined}
            aria-current={active(l.href) ? "page" : undefined}
          >
            <Icon name={l.icon} size={22} />
            {t(l.label)}
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
          {t("nav.more")}
        </button>
      </nav>
    </>
  );
}
