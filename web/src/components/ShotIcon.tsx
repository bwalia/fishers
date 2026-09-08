/// A pictogram per stroke: the field seen from above, the bat in the middle and
/// an arrow where that shot typically goes. Aerial strokes arc, defence and
/// leave have no arrow at all — so the grid can be read at a glance rather than
/// by reading thirteen labels.

export type ShotShape = {
  kind: string;
  label: string;
  /// Bearing in the same system the wagon wheel uses: 0 is straight down the
  /// ground, increasing clockwise for a right-hander.
  angle: number | null;
  aerial?: boolean;
  hint: string;
};

export const SHOT_SHAPES: ShotShape[] = [
  { kind: "drive", label: "Drive", angle: 325, hint: "straight or through cover" },
  { kind: "cut", label: "Cut", angle: 250, hint: "square on the off side" },
  { kind: "pull", label: "Pull", angle: 100, hint: "square on the leg side" },
  { kind: "hook", label: "Hook", angle: 140, aerial: true, hint: "up and round the corner" },
  { kind: "sweep", label: "Sweep", angle: 150, hint: "down to fine leg" },
  { kind: "reverse_sweep", label: "Reverse", angle: 210, hint: "reverse, behind point" },
  { kind: "glance", label: "Glance", angle: 165, hint: "tickled fine" },
  { kind: "flick", label: "Flick", angle: 70, hint: "off the pads to mid-wicket" },
  { kind: "loft", label: "Loft", angle: 10, aerial: true, hint: "over the top" },
  { kind: "defence", label: "Defence", angle: null, hint: "blocked" },
  { kind: "edge", label: "Edge", angle: 200, hint: "thick or thin edge" },
  { kind: "leave", label: "Leave", angle: null, hint: "shouldered arms" },
  { kind: "other", label: "Other", angle: 45, hint: "worked away" },
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
