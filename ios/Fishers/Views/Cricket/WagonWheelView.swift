import SwiftUI

/// The field, drawn from the batter's end: bowler at the top, the rope at the
/// edge. `angle` is 0 straight down the ground and increases clockwise.
private struct FieldBackdrop: View {
    var batsLeft: Bool

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2

            ZStack {
                Circle()
                    .fill(FishersTheme.pitch.opacity(0.10))
                    .frame(width: size, height: size)
                Circle()
                    .strokeBorder(FishersTheme.pitch.opacity(0.35), lineWidth: 1.5)
                    .frame(width: size, height: size)
                // The thirty-yard ring.
                Circle()
                    .strokeBorder(
                        FishersTheme.pitch.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .frame(width: size * 0.55, height: size * 0.55)
                // The pitch.
                RoundedRectangle(cornerRadius: 2)
                    .fill(FishersTheme.maybe.opacity(0.28))
                    .frame(width: size * 0.07, height: size * 0.28)

                ForEach(sectorLabels, id: \.angle) { label in
                    Text(label.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .position(point(centre: centre, radius: radius * 0.86, degrees: label.angle))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var sectorLabels: [(angle: Double, name: String)] {
        stride(from: 22.0, to: 360.0, by: 45.0).map { angle in
            (angle, cricketRegion(angle: UInt16(angle), batsLeft: batsLeft))
        }
    }

    private func point(centre: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        return CGPoint(
            x: centre.x + radius * cos(radians),
            y: centre.y + radius * sin(radians)
        )
    }
}

/// Tap the field to say where the shot went. Used on every scoring shot, so it
/// has to be one tap and never block: `onSkip` is always available.
struct WagonWheelPicker: View {
    let batterName: String
    let batsLeft: Bool
    let runs: Int
    var onSave: (ShotRecord) -> Void
    var onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var angle: UInt16?
    @State private var reach: Double = 0.8
    @State private var kind: ShotKind

    init(
        batterName: String,
        batsLeft: Bool,
        runs: Int,
        onSave: @escaping (ShotRecord) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.batterName = batterName
        self.batsLeft = batsLeft
        self.runs = runs
        self.onSave = onSave
        self.onSkip = onSkip
        _kind = State(initialValue: ShotKind.likely(forRuns: runs).first ?? .drive)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(headline)
                    .font(FishersTheme.subhead)
                    .foregroundStyle(.secondary)

                field
                    .frame(maxWidth: 320, maxHeight: 320)
                    .padding(.horizontal)

                Text(angle == nil ? "Tap where it went" : regionName)
                    .font(FishersTheme.headline)
                    .foregroundStyle(angle == nil ? .secondary : FishersTheme.accent)
                    .animation(.snappy, value: angle)

                shotChips

                Spacer(minLength: 0)
            }
            .padding(.vertical)
            .navigationTitle("Where did it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let angle {
                            onSave(ShotRecord(angle: angle, kind: kind, reach: reach))
                        } else {
                            onSkip()
                        }
                        dismiss()
                    }
                    .bold()
                    .disabled(angle == nil)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var headline: String {
        let outcome: String
        switch runs {
        case 6: outcome = "SIX"
        case 4: outcome = "FOUR"
        case 0: outcome = "no run"
        case 1: outcome = "1 run"
        default: outcome = "\(runs) runs"
        }
        return "\(batterName) — \(outcome)"
    }

    private var regionName: String {
        guard let angle else { return "" }
        return "\(kind.verb.capitalized) to \(cricketRegion(angle: angle, batsLeft: batsLeft))"
    }

    private var field: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2

            ZStack {
                FieldBackdrop(batsLeft: batsLeft)
                if let angle {
                    ShotLine(angle: angle, reach: reach, colour: colour)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        record(value.location, centre: centre, radius: radius)
                    }
            )
            .accessibilityLabel("Wagon wheel. Tap to place the shot.")
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var colour: Color {
        switch runs {
        case 6: return FishersTheme.six
        case 4: return FishersTheme.four
        default: return FishersTheme.accent
        }
    }

    private func record(_ location: CGPoint, centre: CGPoint, radius: CGFloat) {
        let dx = location.x - centre.x
        let dy = location.y - centre.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 4 else { return }
        // 0 is straight down the ground; degrees increase clockwise.
        let degrees = (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        angle = UInt16(degrees.rounded())
        // A boundary always reaches the rope.
        reach = runs >= 4 ? 1.0 : min(1.0, max(0.15, distance / radius))
    }

    /// The strokes as pictograms rather than a row of words — each draws where
    /// that shot goes, so the grid is read at a glance between balls.
    private var shotChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orderedShots) { shot in
                    Button {
                        kind = shot
                    } label: {
                        VStack(spacing: 2) {
                            ShotIconView(kind: shot, size: 36)
                            Text(shot.label)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Text(shot.iconHint)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 92, height: 82)
                        .background(
                            kind == shot
                                ? FishersTheme.accent.opacity(0.18)
                                : Color.secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(kind == shot ? FishersTheme.accent : .clear, lineWidth: 2)
                        )
                        .foregroundStyle(kind == shot ? FishersTheme.accent : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(shot.label), \(shot.iconHint)")
                    .accessibilityAddTraits(kind == shot ? [.isSelected] : [])
                }
            }
            .padding(.horizontal)
        }
    }

    /// The shots that actually produce this many runs, first.
    private var orderedShots: [ShotKind] {
        let likely = ShotKind.likely(forRuns: runs)
        return likely + ShotKind.allCases.filter { !likely.contains($0) }
    }
}

private struct ShotLine: View {
    let angle: UInt16
    let reach: Double
    let colour: Color

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 * reach
            let radians = (Double(angle) - 90) * .pi / 180
            let end = CGPoint(
                x: centre.x + radius * cos(radians),
                y: centre.y + radius * sin(radians)
            )
            ZStack {
                Path { path in
                    path.move(to: centre)
                    path.addLine(to: end)
                }
                .stroke(colour, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle()
                    .fill(colour)
                    .frame(width: 10, height: 10)
                    .position(end)
            }
        }
    }
}

/// Every shot in an innings, drawn as a wheel. The picture a player wants after
/// the game: where their runs came from.
struct WagonWheelChart: View {
    let state: MatchState
    let innings: InningsState
    var batterId: UUID?

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = min(geo.size.width, geo.size.height) / 2

                ZStack {
                    FieldBackdrop(batsLeft: batsLeft)
                    ForEach(shots) { delivery in
                        if let shot = delivery.shot {
                            Path { path in
                                let radians = (Double(shot.angle) - 90) * .pi / 180
                                let length = radius * max(0.15, shot.reach)
                                path.move(to: centre)
                                path.addLine(to: CGPoint(
                                    x: centre.x + length * cos(radians),
                                    y: centre.y + length * sin(radians)
                                ))
                            }
                            .stroke(
                                colour(for: delivery),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            if shots.isEmpty {
                Text("No shots recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 14) {
                    legend(FishersTheme.six, "Six")
                    legend(FishersTheme.four, "Four")
                    legend(FishersTheme.accent, "Runs")
                }
                .font(.caption2)
            }
        }
        .accessibilityLabel(accessibilitySummary)
    }

    private var shots: [DeliveryRecord] {
        innings.shots(for: batterId)
    }

    private var batsLeft: Bool {
        batterId.map { state.batsLeft($0) } ?? false
    }

    private func colour(for delivery: DeliveryRecord) -> Color {
        if delivery.runs >= 6 { return FishersTheme.six }
        if delivery.runs >= 4 { return FishersTheme.four }
        return FishersTheme.accent.opacity(0.65)
    }

    private func legend(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private var accessibilitySummary: String {
        let boundaries = shots.filter { $0.runs >= 4 }.count
        return "Wagon wheel: \(shots.count) shots recorded, \(boundaries) boundaries."
    }
}
