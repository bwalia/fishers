"use client";

import { useEffect, useRef, useState } from "react";
import { Icon, type IconName } from "@/components/Icon";
import { useT } from "@/lib/i18n/provider";

/// The ⋯ menu: things that matter occasionally.
///
/// Sharing a scoreboard, handing the book over, calling a match off — each is
/// important when you want it and noise the rest of the time. On a phone the
/// space above the fold belongs to the score and the dial, so anything used
/// once a match lives behind this.
export function OverflowMenu({
  label,
  children,
  showLabel = false,
  className = "",
  icon = "more",
  chevron = false,
}: {
  label?: string;
  children: React.ReactNode;
  /// Print the label beside the icon — in the top bar, where every other item
  /// has words and an unlabelled "⋯" would be the one nobody finds.
  showLabel?: boolean;
  className?: string;
  /// The group's own icon. A named group ("Play") leading with "⋯" says
  /// "leftovers" when it means "these belong together".
  icon?: IconName;
  /// A chevron after the label, which is what says "this opens" rather than
  /// "this navigates" — the two are otherwise identical in a row of links.
  chevron?: boolean;
}) {
  const t = useT();
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => {
      if (!box.current?.contains(e.target as Node)) setOpen(false);
    };
    const esc = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", away);
    document.addEventListener("keydown", esc);
    return () => {
      document.removeEventListener("mousedown", away);
      document.removeEventListener("keydown", esc);
    };
  }, [open]);

  return (
    <div className={`overflow ${className}`.trim()} ref={box}>
      <button
        type="button"
        className="overflow-button"
        aria-label={label ?? t("le.more")}
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((o) => !o)}
      >
        <Icon name={icon} size={icon === "more" ? 20 : 16} />
        {showLabel && <span>{label ?? t("le.more")}</span>}
        {chevron && <Icon name="chevronDown" size={14} className="overflow-chevron" />}
      </button>
      {open && (
        // Closes on any click inside: every item here either navigates or
        // opens something of its own, so leaving the menu up behind it just
        // covers the thing they asked for.
        <div className="overflow-panel" role="menu" onClick={() => setOpen(false)}>
          {children}
        </div>
      )}
    </div>
  );
}
