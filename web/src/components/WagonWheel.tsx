"use client";

import { regionFor, type Delivery } from "@/lib/cricket";

/// Boundaries get their own colours rather than the theme green, which read as
/// "just another line". Blue and orange stay apart for the common kinds of
/// colour blindness — and the legend means colour is never the only cue.
const RUN_COLOURS = {
  six: "#f2711c",
  four: "#2f80ed",
  other: "#8a8f98",
};

function colourFor(runs: number) {
  if (runs >= 6) return RUN_COLOURS.six;
  if (runs >= 4) return RUN_COLOURS.four;
  return RUN_COLOURS.other;
}

/// The eight sectors, named at their midpoints. `regionFor` decides the name so
/// the label always matches the region that will actually be recorded — which
/// also mirrors it for a left-hander without any extra work here.
const SECTOR_MIDPOINTS = [22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5];

export function WagonWheel({
  deliveries,
  onPick,
  pending,
  batsLeft = false,
  size = 260,
}: {
  deliveries: Delivery[];
  onPick?: (angle: number, reach: number) => void;
  pending?: { angle: number; reach: number } | null;
  batsLeft?: boolean;
  size?: number;
}) {
  const shots = deliveries.filter((d) => d.shot);
  const centre = size / 2;
  // Room inside the rope for the sector names.
  const radius = size / 2 - 6;
  const labelRadius = radius * 0.86;

  const handleClick = (e: React.MouseEvent<SVGSVGElement>) => {
    if (!onPick) return;
    const box = e.currentTarget.getBoundingClientRect();
    // The SVG is scaled to fit, so map the click back into viewBox units.
    const x = ((e.clientX - box.left) / box.width) * size - centre;
    const y = ((e.clientY - box.top) / box.height) * size - centre;
    const degrees = (Math.atan2(y, x) * 180) / Math.PI;
    // Rendering rotates by -90°, so undo that to get a cricket bearing.
    const angle = Math.round((degrees + 90 + 360) % 360);
    const reach = Math.min(1, Math.max(0.1, Math.hypot(x, y) / radius));
    onPick(angle, Number(reach.toFixed(2)));
  };

  const point = (angle: number, distance: number) => {
    const radians = ((angle - 90) * Math.PI) / 180;
    return {
      x: centre + distance * Math.cos(radians),
      y: centre + distance * Math.sin(radians),
    };
  };

  const line = (angle: number, reach: number) => {
    const { x, y } = point(angle, radius * Math.max(0.15, reach));
    return { x2: x, y2: y };
  };

  return (
    <div>
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
        role={onPick ? undefined : "img"}
        onClick={handleClick}
        style={{ cursor: onPick ? "crosshair" : undefined, maxWidth: "100%", height: "auto" }}
        aria-label={
          onPick
            ? undefined
            : `Wagon wheel: ${shots.length} shots, ${shots.filter((s) => s.runs >= 4).length} boundaries`
        }
      >
        <circle cx={centre} cy={centre} r={radius} fill="#1b7f4c11" stroke="#1b7f4c55" />
        <circle
          cx={centre}
          cy={centre}
          r={radius * 0.55}
          fill="none"
          stroke="#1b7f4c33"
          strokeDasharray="4 4"
        />

        {/* sector dividers, so the named areas are visible not just implied */}
        {[0, 45, 90, 135, 180, 225, 270, 315].map((a) => {
          const { x, y } = point(a, radius);
          return (
            <line
              key={a}
              x1={centre}
              y1={centre}
              x2={x}
              y2={y}
              stroke="#1b7f4c22"
              strokeWidth={1}
            />
          );
        })}

        {SECTOR_MIDPOINTS.map((a) => {
          const { x, y } = point(a, labelRadius);
          return (
            <text
              key={a}
              x={x}
              y={y}
              textAnchor="middle"
              dominantBaseline="middle"
              fontSize={size * 0.042}
              fill="currentColor"
              opacity={0.55}
              style={{ pointerEvents: "none", textTransform: "lowercase" }}
            >
              {regionFor(a, batsLeft)}
            </text>
          );
        })}

        {/* the bat */}
        <rect
          x={centre - size * 0.035}
          y={centre - size * 0.14}
          width={size * 0.07}
          height={size * 0.28}
          rx={2}
          fill="#d8a13a55"
        />

        {shots.map((ball, index) => {
          const { x2, y2 } = line(ball.shot!.angle, ball.shot!.reach ?? 0.6);
          return (
            <line
              key={index}
              x1={centre}
              y1={centre}
              x2={x2}
              y2={y2}
              stroke={colourFor(ball.runs)}
              strokeWidth={2}
              strokeLinecap="round"
            />
          );
        })}

        {pending && (
          <>
            <line
              x1={centre}
              y1={centre}
              {...line(pending.angle, pending.reach)}
              stroke="#d8a13a"
              strokeWidth={3}
              strokeLinecap="round"
            />
            <circle
              {...(() => {
                const p = point(pending.angle, radius * Math.max(0.15, pending.reach));
                return { cx: p.x, cy: p.y };
              })()}
              r={4}
              fill="#d8a13a"
            />
          </>
        )}
      </svg>

      {onPick ? (
        <p className="muted" style={{ fontSize: "0.85rem", textAlign: "center" }}>
          {pending
            ? `${regionFor(pending.angle, batsLeft)} · ${pending.angle}°`
            : "Tap the field to place this shot."}
        </p>
      ) : (
        <>
          <p className="muted" style={{ fontSize: "0.8rem" }}>
            {shots.length} shot{shots.length === 1 ? "" : "s"} plotted ·{" "}
            {shots.filter((s) => s.runs >= 4).length} boundaries
          </p>
          <ul className="wheel-legend">
            <li><span style={{ background: RUN_COLOURS.six }} />Six</li>
            <li><span style={{ background: RUN_COLOURS.four }} />Four</li>
            <li><span style={{ background: RUN_COLOURS.other }} />1–3 and dots</li>
          </ul>
        </>
      )}
    </div>
  );
}
