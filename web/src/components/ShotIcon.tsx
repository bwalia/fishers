/// A pictogram per stroke: the field seen from above, the bat in the middle and
/// an arrow where that shot typically goes. Aerial strokes arc, defence and
/// leave have no arrow at all — so the grid can be read at a glance rather than
/// by reading thirteen labels.

export type ShotShape = {
  kind: string;
  /// Bearing in the same system the wagon wheel uses: 0 is straight down the
  /// ground, increasing clockwise for a right-hander.
  angle: number | null;
  aerial?: boolean;
};

export const SHOT_SHAPES: ShotShape[] = [
  { kind: "drive", angle: 325 },
  { kind: "cut", angle: 250 },
  { kind: "pull", angle: 100 },
  { kind: "hook", angle: 140, aerial: true },
  { kind: "sweep", angle: 150 },
  { kind: "reverse_sweep", angle: 210 },
  { kind: "glance", angle: 165 },
  { kind: "flick", angle: 70 },
  { kind: "loft", angle: 10, aerial: true },
  { kind: "defence", angle: null },
  { kind: "edge", angle: 200 },
  { kind: "leave", angle: null },
  { kind: "other", angle: 45 },
];

export function ShotIcon({ shape, size = 44 }: { shape: ShotShape; size?: number }) {
  const c = size / 2;
  const r = c - 3;
  const tip = r * 0.92;

  let arrow = null;
  if (shape.angle !== null) {
    const rad = ((shape.angle - 90) * Math.PI) / 180;
    const x = c + tip * Math.cos(rad);
    const y = c + tip * Math.sin(rad);
    if (shape.aerial) {
      // A curve reads as "in the air" without needing a legend.
      const mx = c + tip * 0.55 * Math.cos(rad - 0.5);
      const my = c + tip * 0.55 * Math.sin(rad - 0.5);
      arrow = <path d={`M${c} ${c} Q${mx} ${my} ${x} ${y}`} strokeWidth={2} />;
    } else {
      arrow = <path d={`M${c} ${c} L${x} ${y}`} strokeWidth={2} />;
    }
  }

  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <circle cx={c} cy={c} r={r} strokeWidth={1} opacity={0.35} />
      {arrow}
      {/* the bat */}
      <rect
        x={c - size * 0.045}
        y={c - size * 0.16}
        width={size * 0.09}
        height={size * 0.3}
        rx={1.5}
        fill="currentColor"
        opacity={0.55}
        stroke="none"
      />
      {shape.kind === "leave" && (
        <path d={`M${c - r * 0.45} ${c - r * 0.45} L${c + r * 0.45} ${c + r * 0.45}`} strokeWidth={1.5} opacity={0.6} />
      )}
    </svg>
  );
}
