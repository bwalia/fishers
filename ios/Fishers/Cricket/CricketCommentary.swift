import Foundation

/// Ball-by-ball commentary, generated from the log rather than typed.
///
/// The event log already knows who bowled to whom, what happened and — when the
/// scorer filled in the wagon wheel — how the shot was played and where it went.
/// That is everything a line of commentary needs.
enum CricketCommentary {
    /// "13.4  Cook to Patel, FOUR — driven through cover"
    static func line(
        for delivery: DeliveryRecord,
        in state: MatchState,
        innings: InningsState
    ) -> String {
        var parts: [String] = []

        let bowler = delivery.bowlerId.map { state.name(for: $0) }
        let batter = delivery.batterId.map { state.name(for: $0) }
        if let bowler, let batter {
            parts.append("\(bowler) to \(batter),")
        } else if let batter {
            parts.append("\(batter),")
        }

        parts.append(outcome(for: delivery, innings: innings))

        if let shot = delivery.shot {
            let left = delivery.batterId.map { state.batsLeft($0) } ?? false
            let region = cricketRegion(angle: shot.angle, batsLeft: left)
            switch shot.kind {
            case .leave:
                parts.append("— left alone")
            case .defence:
                parts.append("— defended")
            default:
                parts.append("— \(shot.kind.verb) \(preposition(for: region)) \(region)")
            }
        }

        return parts.joined(separator: " ")
    }

    /// The over-and-ball marker a scorecard puts in front of the line.
    static func marker(for delivery: DeliveryRecord) -> String {
        "\(delivery.over).\(delivery.ballInOver)"
    }

    /// Newest ball first — how a commentary feed reads.
    static func feed(for innings: InningsState, in state: MatchState, limit: Int = 40) -> [Entry] {
        innings.deliveries.suffix(limit).reversed().map { delivery in
            Entry(
                id: "\(delivery.over).\(delivery.ballInOver)-\(delivery.label)-\(delivery.runs)",
                marker: marker(for: delivery),
                text: line(for: delivery, in: state, innings: innings),
                isWicket: delivery.isWicket,
                isBoundary: delivery.runs >= 4 && !delivery.isWicket
            )
        }
    }

    struct Entry: Identifiable {
        let id: String
        let marker: String
        let text: String
        let isWicket: Bool
        let isBoundary: Bool
    }

    // MARK: - Private

    private static func outcome(for delivery: DeliveryRecord, innings: InningsState) -> String {
        if delivery.isWicket {
            return delivery.runs > 0 ? "OUT (\(delivery.runs) run)" : "OUT"
        }
        if !delivery.isLegal {
            // The label already reads as the scorebook does: wd, nb+4, 5p.
            return extraPhrase(delivery.label, runs: Int(delivery.runs))
        }
        switch delivery.runs {
        case 0: return "no run"
        case 4: return "FOUR"
        case 6: return "SIX"
        case 1: return "1 run"
        default:
            if delivery.label.hasSuffix("b") || delivery.label.hasSuffix("lb") {
                return extraPhrase(delivery.label, runs: Int(delivery.runs))
            }
            return "\(delivery.runs) runs"
        }
    }

    private static func extraPhrase(_ label: String, runs: Int) -> String {
        if label.hasPrefix("wd") {
            return runs > 1 ? "wide, \(runs) runs" : "wide"
        }
        if label.hasPrefix("nb") {
            return runs > 1 ? "no ball, \(runs) runs" : "no ball"
        }
        if label.hasSuffix("lb") { return "\(runs) leg bye\(runs == 1 ? "" : "s")" }
        if label.hasSuffix("b") { return "\(runs) bye\(runs == 1 ? "" : "s")" }
        if label.hasSuffix("p") { return "\(runs) penalty runs" }
        return label
    }

    /// "through cover", but "over long on" for a lofted shot to the rope.
    private static func preposition(for region: String) -> String {
        switch region {
        case "long on", "long off": return "down the ground to"
        case "fine leg", "third man": return "down to"
        default: return "through"
        }
    }
}
