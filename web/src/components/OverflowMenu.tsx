"use client";

import { useEffect, useRef, useState } from "react";
import { Icon } from "@/components/Icon";

/// The ⋯ menu: things that matter occasionally.
///
/// Sharing a scoreboard, handing the book over, calling a match off — each is
/// important when you want it and noise the rest of the time. On a phone the
/// space above the fold belongs to the score and the dial, so anything used
/// once a match lives behind this.
export function OverflowMenu({
  label = "More",
  children,
  showLabel = false,
  className = "",
}: {
  label?: string;
  children: React.ReactNode;
  /// Print the label beside the icon — in the top bar, where every other item
  /// has words and an unlabelled "⋯" would be the one nobody finds.
  showLabel?: boolean;
  className?: string;
}) {
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
        aria-label={label}
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((o) => !o)}
      >
        <Icon name="more" size={20} />
        {showLabel && <span>{label}</span>}
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
