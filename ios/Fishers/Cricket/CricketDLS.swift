import Foundation

/// Duckworth–Lewis–Stern par scores, mirroring `backend/domain/src/cricket/dls.rs`.
///
/// Computed on the device so a rain-hit chase still shows a par score with no
/// signal; the API computes the same numbers from the same log.
///
/// The ICC's licensed Standard Edition table is not reproduced here. This is the
/// published Duckworth–Lewis functional form with parameters fitted to it —
/// accurate to a tenth of a point against the published zero-wicket column, and
/// labelled as an approximation wherever it is shown.
enum CricketDLS {
    static let defaultG50 = 245.0

    private static let decay = 0.0275
    private static let referenceOvers = 50.0

    /// Capacity remaining with `w` wickets down, as a fraction of the
    /// zero-wicket figure. Solved so the fifty-over column matches the table.
    private static let wicketFactors: [Double] = [
        1.0000, 0.8850, 0.7610, 0.6310, 0.5005, 0.3760, 0.2621, 0.1645, 0.0889, 0.0351,
    ]

    /// Resource percentage with `overs` remaining and `wickets` down.
    static func resource(overs: Double, wickets: Int) -> Double {
        guard overs > 0, wickets < 10 else { return 0 }
        let f = wicketFactors[max(0, min(9, wickets))]
        let z = f * (1 - exp(-decay * overs / f))
        let full = 1 - exp(-decay * referenceOvers)
        return z / full * 100
    }

    struct Innings {
        var oversAvailable: Double
        var oversRemaining: Double
        var wicketsLost: Int

        var total: Double { CricketDLS.resource(overs: oversAvailable, wickets: 0) }
        var used: Double {
            max(0, total - CricketDLS.resource(overs: oversRemaining, wickets: wicketsLost))
        }
    }

    /// Par and target for the side batting second.
    static func par(
        firstInningsScore: Int,
        first: Innings,
        second: Innings,
        secondInningsScore: Int,
        g50: Double = defaultG50
    ) -> DlsPar? {
        var r1 = first.total - resource(overs: first.oversRemaining, wickets: first.wicketsLost)
        // A side that batted its overs out used everything it had.
        if r1 <= 0 { r1 = first.total }
        guard r1 > 0 else { return nil }

        let r2Total = second.total
        let r2Used = second.used
        let s1 = Double(firstInningsScore)

        let parScore = Int((s1 * r2Used / r1).rounded(.down))
        let usedG50 = r2Total > r1
        let target = usedG50
            ? Int((s1 + g50 * (r2Total - r1) / 100).rounded(.down)) + 1
            : Int((s1 * r2Total / r1).rounded(.down)) + 1

        return DlsPar(
            par: parScore,
            aheadBy: secondInningsScore - parScore,
            target: target,
            resourcesFirst: (r1 * 10).rounded() / 10,
            resourcesSecond: (r2Total * 10).rounded() / 10,
            resourcesUsed: (r2Used * 10).rounded() / 10,
            method: "standard_approximation",
            usedG50: usedG50
        )
    }
}

extension MatchState {
    /// Where the chase stands on DLS, from the first ball of the second innings.
    var dlsPar: DlsPar? {
        guard innings.count >= 2 else { return nil }
        let first = innings[0]
        let second = innings[1]
        return CricketDLS.par(
            firstInningsScore: Int(first.runs),
            first: CricketDLS.Innings(
                oversAvailable: Double(first.oversAvailable),
                oversRemaining: Double(first.ballsRemaining) / 6.0,
                wicketsLost: Int(first.wickets)
            ),
            second: CricketDLS.Innings(
                oversAvailable: Double(second.oversAvailable),
                oversRemaining: Double(second.ballsRemaining) / 6.0,
                wicketsLost: Int(second.wickets)
            ),
            secondInningsScore: Int(second.runs)
        )
    }
}
