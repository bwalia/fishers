"use client";

import { regionKeyFor, type Delivery } from "@/lib/cricket";
import { useT } from "@/lib/i18n/provider";

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

/// The eight sectors, named at their midpoints. `regionKeyFor` decides the name
/// so the label always matches the region that will actually be recorded —
/// which also mirrors it for a left-hander without any extra work here.
const SECTOR_MIDPOINTS = [22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5];

/// A cricket ground is an oval, not a circle, and it is longer down the ground
/// than it is square. Lord's is about 170 yards straight and 150 square; this
/// is that ratio, and it is the reason the maths below cannot use one radius.
const SQUARE_RATIO = 0.88;

/// Strokes that go up rather than along. Only used for how the line is drawn —
/// what was recorded is the bearing and the reach, same as ever.
const AERIAL = new Set(["loft", "hook"]);

export function WagonWheel({
  deliveries,
  onPick,
  pending,
  batsLeft = false,
  size = 260,
  /// While picking: the bearing this stroke usually goes to, shaded so the tap
  /// is guided. A cut does not go to long on, and a wheel that says so gets
  /// better data out of a scorer in a hurry.
  likelyAngle,
}: {
  deliveries: Delivery[];
  onPick?: (angle: number, reach: number) => void;
  pending?: { angle: number; reach: number } | null;
  batsLeft?: boolean;
  size?: number;
  likelyAngle?: number | null;
}) {
  const t = useT();
  const shots = deliveries.filter((d) => d.shot);
  const centre = size / 2;
  // Room inside the rope for the sector names. They are set on two lines and
  // pulled well inside the rope, because at 0.86 a name like "mid-wicket"
  // reached past the boundary and was clipped by the viewBox.
  //
  // A six is drawn *past* the rope, so the padding has to leave room for it —
  // otherwise the one shot everybody wants to see gets clipped.
  const pad = size * 0.055;
  const down = size / 2 - pad; // semi-axis down the ground
  const square = down * SQUARE_RATIO; // semi-axis square of the wicket

  /// How far the rope is at a given bearing. The whole point of the oval: a
  /// six straight is a longer hit than a six square, and a reach of 1.0 has to
  /// mean "the rope" in both directions.
  const ropeAt = (angle: number) => {
    const radians = ((angle - 90) * Math.PI) / 180;
    const cos = Math.cos(radians);
    const sin = Math.sin(radians);
    return (
      (square * down) / Math.sqrt((down * cos) ** 2 + (square * sin) ** 2)
    );
  };

  const point = (angle: number, distance: number) => {
    const radians = ((angle - 90) * Math.PI) / 180;
    return {
      x: centre + distance * Math.cos(radians),
      y: centre + distance * Math.sin(radians),
    };
  };

  /// Where a shot's line ends.
  ///
  /// A four stops at the rope because that is where it went; a six is drawn
  /// clearing it, which is the one thing a wagon wheel can say that a list of
  /// numbers cannot. Anything else stops at its reach, and a dot is a stub —
  /// the ball did not go anywhere.
  const endOf = (runs: number, angle: number, reach: number) => {
    const rope = ropeAt(angle);
    if (runs >= 6) return rope * 1.08;
    if (runs >= 4) return rope;
    if (runs === 0) return rope * 0.2;
    return rope * Math.min(0.92, Math.max(0.22, reach));
  };

  const handleClick = (e: React.MouseEvent<SVGSVGElement>) => {
    if (!onPick) return;
    const box = e.currentTarget.getBoundingClientRect();
    // The SVG is scaled to fit, so map the click back into viewBox units.
    const x = ((e.clientX - box.left) / box.width) * size - centre;
    const y = ((e.clientY - box.top) / box.height) * size - centre;
    const degrees = (Math.atan2(y, x) * 180) / Math.PI;
    // Rendering rotates by -90°, so undo that to get a cricket bearing.
    const angle = Math.round((degrees + 90 + 360) % 360);
    // Measured against the rope in *that* direction, so a tap on the rope is
    // a reach of 1 whether it is straight or square. Against a single radius
    // the same tap read as 0.88 square and 1.0 straight, and a hit to the
    // longest boundary on the ground came out as the shorter one.
    const reach = Math.min(1, Math.max(0.1, Math.hypot(x, y) / ropeAt(angle)));
    onPick(angle, Number(reach.toFixed(2)));
  };

  /// A struck ball does not travel on a drawn straight line, and one that went
  /// up bends more than one along the ground. A slight bow, away from the
  /// bearing, reads as a path rather than a spoke — and stays legible when
  /// forty of them overlap.
  const pathFor = (angle: number, distance: number, aerial: boolean) => {
    const end = point(angle, distance);
    const bow = aerial ? 0.16 : 0.05;
    const mid = point(angle - bow * 40, distance * 0.55);
    return `M${centre} ${centre} Q${mid.x} ${mid.y} ${end.x} ${end.y}`;
  };

  const shotCount = shots.length;
  const boundaryCount = shots.filter((s) => s.runs >= 4).length;

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
            : t("wheel.aria", { shots: shotCount, boundaries: boundaryCount })
        }
      >
        {/* The outfield, inside the rope. */}
        <ellipse
          cx={centre}
          cy={centre}
          rx={square}
          ry={down}
          fill="#1b7f4c14"
          stroke="#1b7f4c66"
          strokeWidth={1.5}
        />
        {/* The thirty-yard ring — the circle that actually means something in
            cricket, and the one a fielding restriction is written against. */}
        <ellipse
          cx={centre}
          cy={centre}
          rx={square * 0.52}
          ry={down * 0.52}
          fill="none"
          stroke="#1b7f4c40"
          strokeDasharray="5 5"
        />

        {/* Where this stroke usually goes, while one is being picked. */}
        {onPick && likelyAngle != null && (
          <path
            className="wheel-likely"
            d={(() => {
              const spread = 26;
              const from = point(likelyAngle - spread, ropeAt(likelyAngle - spread));
              const to = point(likelyAngle + spread, ropeAt(likelyAngle + spread));
              return `M${centre} ${centre} L${from.x} ${from.y} A${square} ${down} 0 0 1 ${to.x} ${to.y} Z`;
            })()}
          />
        )}

        {/* sector dividers, so the named areas are visible not just implied */}
        {[0, 45, 90, 135, 180, 225, 270, 315].map((a) => {
          const { x, y } = point(a, ropeAt(a));
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
          // 0.7 rather than 0.76, and the smaller type: the names sit at their
          // widest where the oval is narrowest (square of the wicket), and a
          // language whose word for square leg is ਸਕੁਏਅਰ ਲੈੱਗ overflowed the
          // rope there. Sized for the longest name in the longest script, not
          // for English.
          const { x, y } = point(a, ropeAt(a) * 0.7);
          // "mid-wicket" is half as wide over two lines as it is over one.
          const words = t(regionKeyFor(a, batsLeft)).split(/[\s-]/);
          return (
            <text
              key={a}
              x={x}
              y={y}
              textAnchor="middle"
              fontSize={size * 0.038}
              fill="currentColor"
              opacity={0.55}
              style={{ pointerEvents: "none" }}
            >
              {words.map((word, i) => (
                <tspan key={word} x={x} dy={i === 0 ? `${(1 - words.length) * 0.5 + 0.32}em` : "1em"}>
                  {word}
                </tspan>
              ))}
            </text>
          );
        })}

        {/* The square, then the pitch on it, then the creases. A wagon wheel
            without a pitch is a pie chart; with one, which end the batter is
            at is obvious and so is which way is down the ground. */}
        <rect
          x={centre - size * 0.075}
          y={centre - down * 0.3}
          width={size * 0.15}
          height={down * 0.6}
          rx={2}
          fill="#c8b68a26"
        />
        <rect
          x={centre - size * 0.032}
          y={centre - down * 0.26}
          width={size * 0.064}
          height={down * 0.52}
          rx={1}
          fill="#c9ab72"
          opacity={0.5}
        />
        <g stroke="#ffffff" strokeOpacity={0.5} strokeWidth={1}>
          <line x1={centre - size * 0.032} y1={centre - down * 0.2} x2={centre + size * 0.032} y2={centre - down * 0.2} />
          <line x1={centre - size * 0.032} y1={centre + down * 0.2} x2={centre + size * 0.032} y2={centre + down * 0.2} />
        </g>

        {shots.map((ball, index) => {
          const shot = ball.shot!;
          const aerial = AERIAL.has(shot.kind) || ball.runs >= 6;
          const distance = endOf(ball.runs, shot.angle, shot.reach ?? 0.6);
          return (
            <path
              key={index}
              d={pathFor(shot.angle, distance, aerial)}
              fill="none"
              stroke={colourFor(ball.runs)}
              strokeWidth={ball.runs >= 4 ? 2.4 : 1.8}
              strokeLinecap="round"
              opacity={ball.runs === 0 ? 0.5 : 0.9}
            />
          );
        })}

        {pending && (
          <>
            <path
              d={pathFor(pending.angle, ropeAt(pending.angle) * Math.max(0.2, pending.reach), false)}
              fill="none"
              stroke="#d8a13a"
              strokeWidth={3}
              strokeLinecap="round"
            />
            <circle
              {...(() => {
                const p = point(
                  pending.angle,
                  ropeAt(pending.angle) * Math.max(0.2, pending.reach)
                );
                return { cx: p.x, cy: p.y };
              })()}
              r={4.5}
              fill="#d8a13a"
            />
          </>
        )}
      </svg>

      {onPick ? (
        <p className="muted" style={{ fontSize: "0.85rem", textAlign: "center" }}>
          {pending
            ? `${t(regionKeyFor(pending.angle, batsLeft))} · ${pending.angle}°`
            : t("wheel.place")}
        </p>
      ) : (
        <>
          <p className="muted" style={{ fontSize: "0.8rem" }}>
            {t("wheel.plotted", { count: shotCount })} ·{" "}
            {t("wheel.boundaries", { count: boundaryCount })}
          </p>
          <ul className="wheel-legend">
            <li><span style={{ background: RUN_COLOURS.six }} />{t("wheel.legend.six")}</li>
            <li><span style={{ background: RUN_COLOURS.four }} />{t("wheel.legend.four")}</li>
            <li><span style={{ background: RUN_COLOURS.other }} />{t("wheel.legend.other")}</li>
          </ul>
        </>
      )}
    </div>
  );
}
