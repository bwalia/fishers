"use client";

import { useEffect, useState } from "react";
import { enablePush, pushState, type PushState } from "@/lib/push";
import { Icon } from "@/components/Icon";

const DISMISSED = "fishers:push-prompt-dismissed";

/// "Get alerts when Fishers is closed" — one tap, in the places people find
/// they wanted it: the dashboard and their chats.
///
/// The switch itself lives on the Notifications page, where almost nobody goes
/// looking. This only appears while push is off on this device, only until
/// they say "not now", and it never asks the browser for permission unless the
/// button was pressed: an unrequested prompt is the fastest way to be blocked
/// for good, and a denied permission cannot be asked for again.
export function PushPrompt({ context = "chats, invites and fixture news" }: { context?: string }) {
  const [state, setState] = useState<PushState | null>(null);
  const [hidden, setHidden] = useState(true);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    try {
      if (localStorage.getItem(DISMISSED)) return;
    } catch {
      /* no storage: show it */
    }
    setHidden(false);
    pushState().then(setState, () => setState("unsupported"));
  }, []);

  if (hidden || state !== "off") return null;

  const dismiss = () => {
    try {
      localStorage.setItem(DISMISSED, "1");
    } catch {
      /* it just shows again next time */
    }
    setHidden(true);
  };

  return (
    <div className="push-prompt" role="note">
      <span className="push-prompt-icon" aria-hidden="true">
        <Icon name="inbox" size={20} />
      </span>
      <div className="push-prompt-text">
        <strong>Get alerts when Fishers is closed</strong>
        <span className="muted">{`${context[0].toUpperCase()}${context.slice(1)} — straight to this device.`}</span>
      </div>
      <div className="push-prompt-actions">
        <button
          className="btn primary sm"
          type="button"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            try {
              const next = await enablePush();
              setState(next);
              if (next !== "off") dismiss();
            } catch {
              setBusy(false);
            }
          }}
        >
          {busy ? "Turning on…" : "Turn on"}
        </button>
        <button className="btn ghost sm" type="button" onClick={dismiss}>
          Not now
        </button>
      </div>
    </div>
  );
}
