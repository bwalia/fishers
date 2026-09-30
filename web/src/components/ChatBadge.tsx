"use client";

import { useUnreadChats } from "@/lib/inbox";
import { useT } from "@/lib/i18n/provider";

/// How many chat messages are waiting, on the Chats item wherever it appears.
export function ChatBadge() {
  const t = useT();
  const n = useUnreadChats();
  if (n === 0) return null;
  return (
    <span className="nav-badge num">
      {n > 99 ? "99+" : n}
      <span className="sr-only"> {t("rest.unread")}</span>
    </span>
  );
}
