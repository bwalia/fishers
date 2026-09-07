"use client";

import { regionFor, type Delivery } from "@/lib/cricket";

const SIZE = 260;

/// Every plotted shot in one innings, drawn as lines from the middle.
///
/// With `onPick` it doubles as the scorer's input: clicking the field gives the
/// angle and how far it carried, which is all a wagon wheel entry is.
export function WagonWheel({
  deliveries,
  onPick,
  pending,
  batsLeft = false,
}: {
  deliveries: Delivery[];
  onPick?: (angle: number, reach: number) => void;
  pending?: { angle: number; reach: number } | null;
  batsLeft?: boolean;
}) {
  const shots = deliveries.filter((d) => d.shot);
  const centre = SIZE / 2;
  const radius = SIZE / 2 - 6;

  const colour = (ball: Delivery) =>
    ball.runs >= 6 ? "#c62828" : ball.runs >= 4 ? "#1b7f4c" : "#8a8f98";

  const handleClick = (e: React.MouseEvent<SVGSVGElement>) => {
    if (!onPick) return;
    const box = e.currentTarget.getBoundingClientRect();
    // The SVG is scaled to fit, so map the click back into viewBox units.
    const x = ((e.clientX - box.left) / box.width) * SIZE - centre;
    const y = ((e.clientY - box.top) / box.height) * SIZE - centre;
    const degrees = (Math.atan2(y, x) * 180) / Math.PI;
    // Rendering rotates by -90°, so undo that to get a cricket bearing.
    const angle = Math.round((degrees + 90 + 360) % 360);
    const reach = Math.min(1, Math.max(0.1, Math.hypot(x, y) / radius));
    onPick(angle, Number(reach.toFixed(2)));
  };

  const line = (angle: number, reach: number) => {
    const radians = ((angle - 90) * Math.PI) / 180;
    const length = radius * Math.max(0.15, reach);
    return {
      x2: centre + length * Math.cos(radians),
      y2: centre + length * Math.sin(radians),
    };
  };

  return (
    <div>
      <svg
        width={SIZE}
        height={SIZE}
        viewBox={`0 0 ${SIZE} ${SIZE}`}
        role={onPick ? undefined : "img"}
        onClick={handleClick}
        style={{ cursor: onPick ? "crosshair" : undefined, maxWidth: "100%" }}
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
        <rect
          x={centre - SIZE * 0.035}
          y={centre - SIZE * 0.14}
          width={SIZE * 0.07}
          height={SIZE * 0.28}
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
              stroke={colour(ball)}
              strokeWidth={2}
              strokeLinecap="round"
            />
          );
        })}
        {pending && (
          <line
            x1={centre}
            y1={centre}
            {...line(pending.angle, pending.reach)}
            stroke="#d8a13a"
            strokeWidth={3}
            strokeLinecap="round"
          />
        )}
      </svg>
      {onPick ? (
        <p className="muted" style={{ fontSize: "0.8rem" }}>
          {pending
            ? `${pending.angle}° — ${regionFor(pending.angle, batsLeft)}`
            : "Click the field to place the shot."}
        </p>
      ) : (
        <p className="muted" style={{ fontSize: "0.8rem" }}>
          {shots.length} shot{shots.length === 1 ? "" : "s"} plotted ·{" "}
          {shots.filter((s) => s.runs >= 4).length} boundaries
        </p>
      )}
    </div>
  );
}
