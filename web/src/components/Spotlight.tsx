"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

type Box = { top: number; left: number; width: number; height: number };

const PAD = 8; // breathing room between the element and the ring
const GAP = 14; // between the ring and the note

/// One element in focus: the rest of the page dims and blurs, a ring pulses
/// round it, and a note with an arrow says what it does.
///
/// The element itself stays live — pressing it IS the next step, so the tour
/// never stands between somebody and the thing it is pointing at. The dimmed
/// area is four panes around the element rather than one sheet with a hole,
/// because backdrop blur cannot cut a hole in itself.
export function Spotlight({
  targetId,
  step,
  of,
  title,
  body,
  onClose,
  onSkip,
}: {
  targetId: string;
  step: number;
  of: number;
  title: string;
  body: string;
  onClose: () => void;
  /// Ends the whole tour, not just this step.
  onSkip: () => void;
}) {
  const [box, setBox] = useState<Box | null>(null);
  const [note, setNote] = useState({ w: 320, h: 170 });
  const noteRef = useRef<HTMLDivElement>(null);
  const primary = useRef<HTMLButtonElement>(null);

  const measure = useCallback(() => {
    const el = document.getElementById(targetId);
    if (!el) return setBox(null);
    const r = el.getBoundingClientRect();
    setBox({ top: r.top - PAD, left: r.left - PAD, width: r.width + PAD * 2, height: r.height + PAD * 2 });
  }, [targetId]);

  // Bring it into view first, then follow it through scrolls and resizes.
  useEffect(() => {
    const el = document.getElementById(targetId);
    if (!el) {
      onClose();
      return;
    }
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    el.scrollIntoView({ block: "center", behavior: still ? "auto" : "smooth" });
    let frame = 0;
    const follow = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(measure);
    };
    follow();
    // The smooth scroll settles over a few hundred ms; keep up with it.
    const settle = window.setInterval(measure, 60);
    const stop = window.setTimeout(() => window.clearInterval(settle), 900);
    window.addEventListener("scroll", follow, true);
    window.addEventListener("resize", follow);
    return () => {
      cancelAnimationFrame(frame);
      window.clearInterval(settle);
      window.clearTimeout(stop);
      window.removeEventListener("scroll", follow, true);
      window.removeEventListener("resize", follow);
    };
  }, [targetId, measure, onClose]);

  useLayoutEffect(() => {
    const n = noteRef.current;
    if (n) setNote({ w: n.offsetWidth, h: n.offsetHeight });
  }, [box !== null, title, body]);

  useEffect(() => {
    primary.current?.focus({ preventScroll: true });
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  if (!box || typeof document === "undefined") return null;

  const vw = window.innerWidth;
  const vh = window.innerHeight;
  // Below the element when the note fits there; above it otherwise.
  const below = box.top + box.height + GAP + note.h < vh - 12 || box.top - GAP - note.h < 12;
  const noteTop = below ? box.top + box.height + GAP : box.top - GAP - note.h;
  const centre = box.left + box.width / 2;
  const noteLeft = Math.min(Math.max(12, centre - note.w / 2), vw - note.w - 12);
  const arrowX = Math.min(Math.max(22, centre - noteLeft), note.w - 22);

  const right = box.left + box.width;
  const bottom = box.top + box.height;

  return createPortal(
    <div className="spot" aria-live="polite">
      {/* Four panes around the element; clicks on them do nothing, so the
          only ways on are the element, the note's buttons, or Escape. */}
      <div className="spot-pane" style={{ top: 0, left: 0, right: 0, height: Math.max(0, box.top) }} />
      <div className="spot-pane" style={{ top: bottom, left: 0, right: 0, bottom: 0 }} />
      <div className="spot-pane" style={{ top: box.top, left: 0, width: Math.max(0, box.left), height: box.height }} />
      <div className="spot-pane" style={{ top: box.top, left: right, right: 0, height: box.height }} />

      <div className="spot-ring" style={box} aria-hidden="true" />

      <div
        ref={noteRef}
        className={`spot-note ${below ? "below" : "above"}`}
        style={{ top: noteTop, left: noteLeft }}
        role="dialog"
        aria-modal="false"
        aria-labelledby="spot-title"
        aria-describedby="spot-body"
      >
        <span className="spot-arrow" style={{ left: arrowX }} aria-hidden="true" />
        <p className="spot-step">
          Step {step} of {of}
        </p>
        <h2 id="spot-title">{title}</h2>
        <p id="spot-body">{body}</p>
        <div className="spot-actions">
          <button type="button" className="linkish" onClick={onSkip}>
            Skip the tour
          </button>
          <button ref={primary} type="button" className="btn primary sm" onClick={onClose}>
            Got it
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
}
