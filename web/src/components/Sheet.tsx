"use client";

import { useEffect } from "react";

/// A bottom sheet. Escape closes it, and the backdrop is a real button so a
/// keyboard user is never trapped.
export function Sheet({
  title,
  step,
  of,
  onClose,
  children,
}: {
  title: string;
  step?: number;
  of?: number;
  onClose: () => void;
  children: React.ReactNode;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      className="sheet-backdrop"
      role="presentation"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title}>
        <div className="sheet-head">
          <h2>{title}</h2>
          <button className="btn ghost sm" type="button" onClick={onClose} aria-label="Close">
            Close
          </button>
        </div>
        {of && (
          <div className="sheet-steps" aria-hidden="true">
            {Array.from({ length: of }, (_, i) => (
              <span key={i} className={i < (step ?? 0) ? "on" : undefined} />
            ))}
          </div>
        )}
        {children}
      </div>
    </div>
  );
}
