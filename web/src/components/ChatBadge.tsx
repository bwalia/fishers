"use client";

import { useUnreadChats } from "@/lib/inbox";

/// How many chat messages are waiting, on the Chats item wherever it appears.
export function ChatBadge() {
  const n = useUnreadChats();
  if (n === 0) return null;
  return (
    <span className="nav-badge num">
      {n > 99 ? "99+" : n}
      <span className="sr-only"> unread</span>
    </span>
  );
}
