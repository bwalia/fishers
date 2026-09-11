"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { readErr } from "@/lib/api";
import { messagePerson } from "@/lib/chat";
import { Icon } from "@/components/Icon";

/// Opens your chat with this person — the same one every time, started on the
/// first tap.
export function MessageButton({ userId, name, compact = false }: { userId: string; name: string; compact?: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const first = name.split(" ")[0];

  return (
    <>
      <button
        className={compact ? "btn ghost sm icon-only" : "btn"}
        type="button"
        disabled={busy}
        aria-label={compact ? `Message ${name}` : undefined}
        title={error ?? (compact ? `Message ${first}` : undefined)}
        onClick={async () => {
          setBusy(true);
          setError(null);
          try {
            router.push(`/chat/${await messagePerson(userId, name)}`);
          } catch (err) {
            setError(readErr(err, "Could not open the chat"));
            setBusy(false);
          }
        }}
      >
        <Icon name="chat" size={16} />
        {!compact && (busy ? " Opening…" : ` Message ${first}`)}
      </button>
      {error && !compact && <p className="error">{error}</p>}
    </>
  );
}
