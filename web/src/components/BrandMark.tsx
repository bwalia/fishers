"use client";

import { useId } from "react";

/// The club's mark: a cricket ball, seam on.
///
/// Deliberately not part of the line-art `Icon` set — those are interface
/// furniture drawn in whatever colour their surroundings use, and a badge has
/// to be itself wherever it lands: the top bar, a browser tab, a phone's home
/// screen, a notification. Leather, a seam and its stitching, shaded so it
/// reads as a ball rather than a circle, and still legible at 16 pixels where
/// all that survives is a red disc with a pale seam.
///
/// The gradients are given ids of their own per instance: two of these on one
/// page sharing an id would both take the first one's fill.
export function BrandMark({
  size = 24,
  className,
}: {
  size?: number;
  className?: string;
}) {
  const id = useId().replace(/:/g, "");
  const leather = `ball-leather-${id}`;
  const sheen = `ball-sheen-${id}`;
  const edge = `ball-edge-${id}`;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 48 48"
      className={className}
      role="img"
      aria-label="Fishers"
      focusable="false"
    >
      <defs>
        <radialGradient id={leather} cx="34%" cy="28%" r="80%">
          <stop offset="0%" stopColor="#c8483d" />
          <stop offset="45%" stopColor="#9d2b2b" />
          <stop offset="88%" stopColor="#6b1b1b" />
          <stop offset="100%" stopColor="#4a1111" />
        </radialGradient>
        <linearGradient id={sheen} x1="15%" y1="5%" x2="75%" y2="75%">
          <stop offset="0%" stopColor="#ffffff" stopOpacity=".42" />
          <stop offset="65%" stopColor="#ffffff" stopOpacity="0" />
        </linearGradient>
        {/* The seam's band is wider than the ball at top and bottom; without
            this it pokes out past the leather. */}
        <clipPath id={edge}>
          <circle cx="24" cy="24" r="21" />
        </clipPath>
      </defs>
      <circle cx="24" cy="24" r="21" fill={`url(#${leather})`} />
      <ellipse
        cx="16.5"
        cy="14.5"
        rx="11"
        ry="7.5"
        fill={`url(#${sheen})`}
        transform="rotate(-28 16.5 14.5)"
      />
      {/* The seam, seen side on: a darker band of leather, the thread, and the
          stitches straddling it. */}
      <g clipPath={`url(#${edge})`}>
        {/* The seam: a darker band of leather down the middle, the thread
            along it, and the stitches pulling in from either side. */}
        <path d="M24 3v42" fill="none" stroke="#741d1d" strokeWidth="5" strokeLinecap="round" opacity=".5" />
        <path d="M24 3v42" fill="none" stroke="#f4ecdd" strokeWidth="1.4" strokeLinecap="round" />
        <g stroke="#f4ecdd" strokeWidth="1.25" strokeLinecap="round">
          <path d="M20.4 10.4l3.2 1.6M20.0 16.4l3.6 1.2M19.8 22.6l3.8 .6M19.8 28.8l3.8-.6M20.0 34.8l3.6-1.2M20.4 40.6l3.2-1.6" />
          <path d="M27.6 10.4l-3.2 1.6M28.0 16.4l-3.6 1.2M28.2 22.6l-3.8 .6M28.2 28.8l-3.8-.6M28.0 34.8l-3.6-1.2M27.6 40.6l-3.2-1.6" />
        </g>
      </g>
    </svg>
  );
}
