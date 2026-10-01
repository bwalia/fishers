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

/// The ground as drawn: wider across than it is deep, the same shape and the
/// same ratio as the ground on the scoring panel.
///
/// A real one is the other way round — longer straight than square, Lord's
/// being about 170 yards by 150 — and drawn that way it is a tall oval in a
/// square box with empty corners either side. This is that ground seen from a
/// stand rather than from directly overhead, which is how anybody has actually
/// looked at one, and it is why the maths below cannot use a single radius.
const GROUND_RATIO = 1.25;

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
  // `size` is the width; the height follows from the ratio.
  const height = size / GROUND_RATIO;
  const cx = size / 2;
  const cy = height / 2;
  // Room inside the rope for the sector names. They are set on two lines and
  // pulled well inside the rope, because at 0.86 a name like "mid-wicket"
  // reached past the boundary and was clipped by the viewBox.
  //
  // A six is drawn *past* the rope, so the padding has to leave room for it —
  // otherwise the one shot everybody wants to see gets clipped.
  const pad = size * 0.055;
  const square = size / 2 - pad; // semi-axis square of the wicket
  const down = height / 2 - pad; // semi-axis down the ground

  /// A bearing, in radians, on the screen.
  ///
  /// Straight down the ground is 0° and it points *down* the picture: the
  /// striker is in the middle looking that way, which puts long on and long
  /// off at the bottom, where somebody standing behind the batter expects
  /// them. It used to point up — the same ground seen from the bowler's end,
  /// which reads back to front to the person scoring.
  ///
  /// Bearings run anticlockwise on the screen, which puts the off side on the
  /// left for a right-hander: straight drive at the bottom, on drive and pull
  /// to the right, cover and the cuts to the left. That is the field as it is
  /// drawn in every coaching diagram, and it is the view from behind the
  /// bowler's arm — the one angle everybody has watched cricket from.
  ///
  /// Clockwise put the off side on the right, which is a left-hander's field.
  /// Note this is a reflection and not a rotation, so anything drawn with a
  /// sweep direction — the shaded sector below — turns the other way too.
  ///
  /// This is the only place the orientation lives, and nothing recorded
  /// changes with it: a bearing is a bearing, and only the picture turns.
  const radiansOf = (angle: number) => ((90 - angle) * Math.PI) / 180;

  /// How far the rope is at a given bearing. The whole point of the oval: a
  /// six square is a longer hit than a six straight on a ground drawn this
  /// way, and a reach of 1.0 has to mean "the rope" in both directions.
  const ropeAt = (angle: number) => {
    const radians = radiansOf(angle);
    const cos = Math.cos(radians);
    const sin = Math.sin(radians);
    return (
      (square * down) / Math.sqrt((down * cos) ** 2 + (square * sin) ** 2)
    );
  };

  const point = (angle: number, distance: number) => {
    const radians = radiansOf(angle);
    return {
      x: cx + distance * Math.cos(radians),
      y: cy + distance * Math.sin(radians),
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
    const x = ((e.clientX - box.left) / box.width) * size - cx;
    const y = ((e.clientY - box.top) / box.height) * height - cy;
    const degrees = (Math.atan2(y, x) * 180) / Math.PI;
    // The inverse of `radiansOf`, so a tap lands on the sector it was aimed at.
    const angle = Math.round((((90 - degrees) % 360) + 360) % 360);
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
    return `M${cx} ${cy} Q${mid.x} ${mid.y} ${end.x} ${end.y}`;
  };

  const shotCount = shots.length;
  const boundaryCount = shots.filter((s) => s.runs >= 4).length;

  return (
    <div>
      <svg
        width={size}
        height={height}
        viewBox={`0 0 ${size} ${height}`}
        role={onPick ? undefined : "img"}
        onClick={handleClick}
        style={{
          cursor: onPick ? "crosshair" : undefined,
          display: "block",
          width: "100%",
          maxWidth: size,
          height: "auto",
          margin: "0 auto",
        }}
        aria-label={
          onPick
            ? undefined
            : t("wheel.aria", { shots: shotCount, boundaries: boundaryCount })
        }
      >
        {/* The outfield, inside the rope. */}
        <ellipse
          cx={cx}
          cy={cy}
          rx={square}
          ry={down}
          fill="#1b7f4c14"
          stroke="#1b7f4c66"
          strokeWidth={1.5}
        />
        {/* The thirty-yard ring — the circle that actually means something in
            cricket, and the one a fielding restriction is written against. */}
        <ellipse
          cx={cx}
          cy={cy}
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
              // Sweep 0: bearings run anticlockwise on the screen, so the
              // arc from `-spread` to `+spread` does too.
              return `M${cx} ${cy} L${from.x} ${from.y} A${square} ${down} 0 0 0 ${to.x} ${to.y} Z`;
            })()}
          />
        )}

        {/* sector dividers, so the named areas are visible not just implied */}
        {[0, 45, 90, 135, 180, 225, 270, 315].map((a) => {
          const { x, y } = point(a, ropeAt(a));
          return (
            <line
              key={a}
              x1={cx}
              y1={cy}
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

        {/* The square, the pitch on it, the creases — and the batter.
            A wagon wheel without a pitch is a pie chart. The pitch runs from
            the middle *away* from the reader, because the middle is where the
            striker is standing: every line on this picture starts from them.
            The bowler is at the far end, which is why long on and long off are
            the sectors beyond it.

            The batter is marked rather than left to be inferred, and sits just
            behind the striker's crease — on the middle itself the lines
            radiating out would cross it. */}
        <rect
          x={cx - size * 0.05}
          y={cy - down * 0.16}
          width={size * 0.1}
          height={down * 0.66}
          rx={2}
          fill="#c8b68a26"
        />
        <rect
          x={cx - size * 0.022}
          y={cy - down * 0.12}
          width={size * 0.044}
          height={down * 0.58}
          rx={1}
          fill="#c9ab72"
          opacity={0.5}
        />
        <g stroke="#ffffff" strokeOpacity={0.5} strokeWidth={1}>
          {/* The striker's crease, then the bowler's at the far end. */}
          <line x1={cx - size * 0.022} y1={cy - down * 0.05} x2={cx + size * 0.022} y2={cy - down * 0.05} />
          <line x1={cx - size * 0.022} y1={cy + down * 0.4} x2={cx + size * 0.022} y2={cy + down * 0.4} />
        </g>
        <g style={{ pointerEvents: "none" }}>
          {/* Stumps and a bat, at the striker's end. */}
          <g stroke="#1b7f4c" strokeOpacity={0.8} strokeWidth={1.4} strokeLinecap="round">
            <line x1={cx - size * 0.013} y1={cy - down * 0.13} x2={cx - size * 0.013} y2={cy - down * 0.07} />
            <line x1={cx} y1={cy - down * 0.13} x2={cx} y2={cy - down * 0.07} />
            <line x1={cx + size * 0.013} y1={cy - down * 0.13} x2={cx + size * 0.013} y2={cy - down * 0.07} />
          </g>
          <line
            x1={cx + size * 0.032}
            y1={cy - down * 0.13}
            x2={cx + size * 0.046}
            y2={cy - down * 0.05}
            stroke="#1b7f4c"
            strokeOpacity={0.8}
            strokeWidth={size * 0.012}
            strokeLinecap="round"
          />
          <text
            x={cx}
            y={cy - down * 0.19}
            textAnchor="middle"
            fontSize={size * 0.03}
            fontWeight={600}
            fill="currentColor"
            opacity={0.7}
          >
            {t("wheel.batter")}
          </text>
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
