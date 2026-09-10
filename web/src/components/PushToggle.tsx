"use client";

import { useCallback, useEffect, useState } from "react";
import { api, readErr } from "@/lib/api";
import { disablePush, enablePush, pushState, type PushState } from "@/lib/push";
import { Icon } from "@/components/Icon";

/// Turning browser notifications on.
///
/// Renders nothing when the server has no keys or the browser cannot do it —
/// a switch that cannot be switched is worse than no switch. It never asks for
/// permission on its own: a prompt somebody did not press a button for is the
/// fastest way to get blocked for good, and a denied permission cannot be
/// asked for again.
export function PushToggle() {
  const [state, setState] = useState<PushState | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(() => {
    pushState().then(setState).catch(() => setState("unsupported"));
  }, []);

  useEffect(() => {
    refresh();

    // The browser can rotate a subscription without asking. The worker tells
    // any open tab, and the tab has the token needed to register the new one.
    const onMessage = (event: MessageEvent) => {
      if (event.data?.type !== "push-subscription-changed") return;
      api("POST", "/notifications/register-device", {
        device_token: JSON.stringify(event.data.subscription),
        platform: "web",
      }).catch(() => {});
    };
    navigator.serviceWorker?.addEventListener("message", onMessage);
    return () => navigator.serviceWorker?.removeEventListener("message", onMessage);
  }, [refresh]);

  // Nothing to offer: no keys on the server, or a browser that cannot.
  if (state === null || state === "unconfigured" || state === "unsupported") return null;

  const toggle = async () => {
    setBusy(true);
    setError(null);
    try {
      setState(state === "on" ? await disablePush() : await enablePush());
    } catch (err) {
      setError(readErr(err, "Could not change that"));
      refresh();
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel push-toggle">
      <div>
        <h2>
          <Icon name="inbox" size={18} /> Notifications on this device
        </h2>
        {state === "denied" ? (
          <p className="muted">
            This browser is blocking notifications from Fishers. It will not ask again — you
            can turn them back on in the site settings, usually behind the padlock in the
            address bar.
          </p>
        ) : state === "on" ? (
          <p className="muted">
            On. You will hear about squads, fixtures and match fees even when this tab is
            closed.
          </p>
        ) : (
          <p className="muted">
            Off. Turn them on to hear when you are picked, when a fixture moves, and when
            somebody needs an answer — without keeping this open.
          </p>
        )}
        {error && <p className="error">{error}</p>}
      </div>

      {state !== "denied" && (
        <button
          className={state === "on" ? "btn" : "btn primary"}
          type="button"
          disabled={busy}
          onClick={toggle}
        >
          {busy ? "…" : state === "on" ? "Turn off" : "Turn on"}
        </button>
      )}
    </div>
  );
}
