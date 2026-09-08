import SwiftUI

/// A pictogram per stroke, mirroring `web/src/components/ShotIcon.tsx`: the
/// field from above, the bat in the middle, and an arrow where that shot
/// usually goes. Aerial strokes arc; a block or a leave has no arrow at all.
///
/// A grid of these reads at a glance, where a row of thirteen words has to be
/// read one at a time — and a scorer is picking this between balls.
struct ShotIconView: View {
    let kind: ShotKind
    var size: CGFloat = 40

    var body: some View {
        Canvas { context, canvasSize in
            let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - 2
            let tip = radius * 0.92

            context.stroke(
                Path(ellipseIn: CGRect(
                    x: centre.x - radius, y: centre.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(.secondary.opacity(0.35)),
                lineWidth: 1
            )

            if let bearing = kind.iconBearing {
                let radians = (bearing - 90) * .pi / 180
                let end = CGPoint(
                    x: centre.x + tip * cos(radians),
                    y: centre.y + tip * sin(radians)
                )
                var path = Path()
                path.move(to: centre)
                if kind.isAerial {
                    // A curve reads as "in the air" without needing a legend.
                    let control = CGPoint(
                        x: centre.x + tip * 0.55 * cos(radians - 0.5),
                        y: centre.y + tip * 0.55 * sin(radians - 0.5)
                    )
                    path.addQuadCurve(to: end, control: control)
                } else {
                    path.addLine(to: end)
                }
                context.stroke(
                    path,
                    with: .color(.primary),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }

            // The bat.
            let bat = CGRect(
                x: centre.x - canvasSize.width * 0.045,
                y: centre.y - canvasSize.height * 0.16,
                width: canvasSize.width * 0.09,
                height: canvasSize.height * 0.3
            )
            context.fill(
                Path(roundedRect: bat, cornerRadius: 1.5),
                with: .color(.primary.opacity(0.55))
            )

            if kind == .leave {
                var slash = Path()
                slash.move(to: CGPoint(x: centre.x - radius * 0.45, y: centre.y - radius * 0.45))
                slash.addLine(to: CGPoint(x: centre.x + radius * 0.45, y: centre.y + radius * 0.45))
                context.stroke(
                    slash,
                    with: .color(.primary.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension ShotKind {
    /// Where this stroke typically goes, in the same bearings the wagon wheel
    /// uses: 0 straight down the ground, increasing clockwise. `nil` for the
    /// strokes that go nowhere.
    var iconBearing: Double? {
        switch self {
        case .drive: return 325
        case .cut: return 250
        case .pull: return 100
        case .hook: return 140
        case .sweep: return 150
        case .reverseSweep: return 210
        case .glance: return 165
        case .flick: return 70
        case .loft: return 10
        case .edge: return 200
        case .other: return 45
        case .defence, .leave: return nil
        }
    }

    var isAerial: Bool {
        self == .loft || self == .hook
    }

    /// A few words on where it goes, so the grid is readable without knowing
    /// the bearings by heart.
    var iconHint: String {
        switch self {
        case .drive: return "straight or cover"
        case .cut: return "square, off side"
        case .pull: return "square, leg side"
        case .hook: return "up round the corner"
        case .sweep: return "down to fine leg"
        case .reverseSweep: return "reverse, behind point"
        case .glance: return "tickled fine"
        case .flick: return "off the pads"
        case .loft: return "over the top"
        case .defence: return "blocked"
        case .edge: return "thick or thin"
        case .leave: return "shouldered arms"
        case .other: return "worked away"
        }
    }
}
