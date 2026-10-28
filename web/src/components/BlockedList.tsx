"use client";

import { useCallback, useEffect, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { useT } from "@/lib/i18n/provider";
import { listBlocks, unblockUser, type BlockedUser } from "@/lib/api";

/// Who you have blocked, and the way back. A block you cannot undo is a
/// setting you are stuck with, so the list is as much a part of blocking as
/// the button that does it.
///
/// It shows only your own blocks. The symmetric half — people who blocked you
/// — is deliberately absent: telling you would tell you they had.
export function BlockedList() {
  const t = useT();
  const [blocked, setBlocked] = useState<BlockedUser[] | null>(null);

  const load = useCallback(async () => {
    try {
      setBlocked(await listBlocks());
    } catch {
      setBlocked([]);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function lift(user: BlockedUser) {
    // Dropped from the list first: the row is gone either way, and leaving it
    // sitting there while the request flies looks like nothing happened.
    setBlocked((prev) => prev?.filter((b) => b.id !== user.id) ?? null);
    try {
      await unblockUser(user.id);
    } catch {
      void load();
    }
  }

  // Nothing at all until it has loaded, and nothing if there is nothing: an
  // empty "people you have blocked" is a question nobody asked.
  if (!blocked || blocked.length === 0) return null;

  return (
    <div className="panel" id="blocked">
      <h2>{t("mod.blocked_people")}</h2>
      <ul className="blocked-list">
        {blocked.map((user) => (
          <li key={user.id}>
            <Avatar name={user.name} size={30} />
            <span>{user.name}</span>
            <button className="btn ghost sm" type="button" onClick={() => void lift(user)}>
              {t("mod.unblock")}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
