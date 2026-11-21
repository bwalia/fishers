"use client";

import { useEffect, useRef, useState } from "react";
import { copyText } from "@/lib/clipboard";
import { useT } from "@/lib/i18n/provider";

/// Copy one value — a sort code, an account number — with a "Copied" that
/// can be seen as well as heard.
///
/// `what` names the value for a screen reader ("Copy account number"), so a
/// row of identical "Copy" buttons is still a row of different buttons. The
/// value itself is never logged: it can be a full account number.
export function CopyButton({
  text,
  what,
  label,
  className = "btn",
}: {
  text: string;
  /// What is being copied, in words: "account number".
  what: string;
  /// The visible word; "Copy" unless said otherwise.
  label?: string;
  className?: string;
}) {
  const t = useT();
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  const timer = useRef<number | null>(null);
  useEffect(() => () => {
    if (timer.current) window.clearTimeout(timer.current);
  }, []);

  const copy = async () => {
    const ok = await copyText(text);
    setState(ok ? "copied" : "failed");
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setState("idle"), 2500);
  };

  return (
    <span className="copy-wrap">
      <button
        type="button"
        className={`${className}${state === "copied" ? " is-copied" : ""}`}
        aria-label={t("pay.copy_what", { what })}
        onClick={() => void copy()}
      >
        {state === "copied" ? t("le.copied") : label ?? t("cl.copy")}
      </button>
      {/* The button itself says "Copied"; this announces it. A failure is
          shown as well, because then the only way left is to select the
          value by hand. */}
      <span className={state === "failed" ? "copy-said" : "sr-only"} role="status" aria-live="polite">
        {state === "copied" ? t("pay.copied_what", { what }) : state === "failed" ? t("pay.copy_failed") : ""}
      </span>
    </span>
  );
}
