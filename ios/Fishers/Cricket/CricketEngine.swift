import Foundation

/// On-device cricket scoring engine — mirrors `backend/domain/src/cricket/engine.rs`.
extension MatchState {
    mutating func apply(_ event: ScoringEvent) throws {
        if event.seq != lastSeq + 1 && !(lastSeq == 0 && event.seq == 1) {
            if event.seq <= lastSeq { return }
            if event.seq != lastSeq + 1 {
                throw CricketEngineError.conflict("expected seq \(lastSeq + 1), got \(event.seq)")
            }
        }

        switch event.kind {
        case .undoLast:
            try restoreHistory()
            lastSeq = event.seq
            return
        default:
            pushHistory()
        }

        switch event.kind {
        case let .matchPrepared(overs, home, away):
            oversLimit = overs
            homeName = home
            awayName = away
            status = .preparing
        case let .tossRecorded(winner, decision):
            tossWinner = winner
            tossDecision = decision
            status = .selectingXi
        case let .xiSelected(side, playerIds, captainId, keeperId):
            guard playerIds.count == 11 else {
                throw CricketEngineError.validation("playing XI must be 11")
            }
            switch side {
            case .home:
                homeXi = playerIds; homeCaptain = captainId; homeKeeper = keeperId
            case .away:
                awayXi = playerIds; awayCaptain = captainId; awayKeeper = keeperId
            }
            if homeXi.count == 11 && awayXi.count == 11 {
                status = .ready
            }
        case let .inningsStarted(idx, batting, striker, non, bowler):
            let battingXi = batting == .home ? homeXi : awayXi
            var batters = battingXi.map { BatterStats(playerId: $0) }
            for id in [striker, non] where !batters.contains(where: { $0.playerId == id }) {
                batters.append(BatterStats(playerId: id))
            }
            var inn = InningsState(index: idx, batting: batting, bowling: batting.opposite)
            inn.batters = batters
            inn.strikerId = striker
            inn.nonStrikerId = non
            inn.bowlerId = bowler
            inn.ensureBowler(bowler)
            innings.append(inn)
            status = .live
            if idx == 1, let first = innings.first {
                target = first.runs + 1
            }
        case let .deliveryRecorded(runs, isLegal, four, six):
            try applyDelivery(runs: runs, isLegal: isLegal, four: four, six: six)
        case let .extrasRecorded(kind, runs):
            try applyExtras(kind: kind, runs: runs)
        case let .wicketRecorded(batterId, kind, _, newBatterId):
            try applyWicket(batterId: batterId, kind: kind, newBatterId: newBatterId)
        case let .bowlerChanged(bowlerId):
            guard !innings.isEmpty else { throw CricketEngineError.validation("no innings") }
            innings[innings.count - 1].ensureBowler(bowlerId)
            innings[innings.count - 1].bowlerId = bowlerId
            innings[innings.count - 1].ballsInCurrentOver = 0
        case .inningsCompleted:
            try completeInnings()
        case let .matchCompleted(winner, margin):
            self.winner = winner
            self.margin = margin
            status = .complete
        case .undoLast:
            break
        }

        lastSeq = event.seq
        try checkAutoComplete()
    }

    // MARK: - Private

    private mutating func pushHistory() {
        history.append(MatchStateSnapshot(
            status: status, innings: innings, target: target, winner: winner, margin: margin
        ))
        if history.count > 200 { history.removeFirst() }
    }

    private mutating func restoreHistory() throws {
        guard let snap = history.popLast() else {
            throw CricketEngineError.validation("nothing to undo")
        }
        status = snap.status
        innings = snap.innings
        target = snap.target
        winner = snap.winner
        margin = snap.margin
    }

    private mutating func applyDelivery(runs: UInt8, isLegal: Bool, four: Bool, six: Bool) throws {
        guard !innings.isEmpty else { throw CricketEngineError.validation("no live innings") }
        let idx = innings.count - 1
        guard !innings[idx].complete else { throw CricketEngineError.validation("innings complete") }
        guard let striker = innings[idx].strikerId else {
            throw CricketEngineError.validation("no striker")
        }
        guard let bowler = innings[idx].bowlerId else {
            throw CricketEngineError.validation("no bowler")
        }

        innings[idx].runs += UInt16(runs)
        let bi = try innings[idx].batterMut(striker)
        innings[idx].batters[bi].runs += UInt16(runs)
        if isLegal { innings[idx].batters[bi].balls += 1 }
        if four { innings[idx].batters[bi].fours += 1 }
        if six { innings[idx].batters[bi].sixes += 1 }

        let boi = try innings[idx].bowlerMut(bowler)
        innings[idx].bowlers[boi].runs += UInt16(runs)
        innings[idx].bowlers[boi].currentOverRuns += UInt16(runs)
        if isLegal { innings[idx].bowlers[boi].balls += 1 }

        let label: String
        if six { label = "SIX" }
        else if four { label = "FOUR" }
        else if runs == 0 { label = "0" }
        else { label = "\(runs)" }

        let over = innings[idx].legalBalls / 6
        let ballIn = innings[idx].ballsInCurrentOver + (isLegal ? 1 : 0)
        innings[idx].deliveries.append(DeliveryRecord(
            over: over, ballInOver: ballIn, label: label,
            runs: runs, isLegal: isLegal, isWicket: false
        ))

        if isLegal {
            innings[idx].legalBalls += 1
            innings[idx].ballsInCurrentOver += 1
            if runs % 2 == 1 { innings[idx].swapStrike() }
            if innings[idx].ballsInCurrentOver >= 6 {
                if let boi = innings[idx].bowlers.firstIndex(where: { $0.playerId == bowler }) {
                    if innings[idx].bowlers[boi].currentOverRuns == 0 {
                        innings[idx].bowlers[boi].maidens += 1
                    }
                    innings[idx].bowlers[boi].currentOverRuns = 0
                }
                innings[idx].ballsInCurrentOver = 0
                innings[idx].swapStrike()
            }
        }

        let ballsCap = UInt16(oversLimit) * 6
        if innings[idx].legalBalls >= ballsCap || innings[idx].wickets >= 10 {
            innings[idx].complete = true
        }
    }

    private mutating func applyExtras(kind: ExtraKind, runs: UInt8) throws {
        guard !innings.isEmpty else { throw CricketEngineError.validation("no live innings") }
        let idx = innings.count - 1
        guard let bowler = innings[idx].bowlerId else {
            throw CricketEngineError.validation("no bowler")
        }
        guard let striker = innings[idx].strikerId else {
            throw CricketEngineError.validation("no striker")
        }

        let teamRuns: UInt8
        let legal: Bool
        let batRuns: UInt8
        let bowlRuns: UInt8
        switch kind {
        case .wide:
            teamRuns = max(runs, 1); legal = false; batRuns = 0; bowlRuns = max(runs, 1)
        case .noBall:
            teamRuns = max(runs, 1); legal = false
            batRuns = runs > 0 ? runs - 1 : 0; bowlRuns = max(runs, 1)
        case .bye, .legBye:
            teamRuns = runs; legal = true; batRuns = 0; bowlRuns = 0
        case .penalty:
            teamRuns = runs; legal = false; batRuns = 0; bowlRuns = 0
        }

        innings[idx].runs += UInt16(teamRuns)
        innings[idx].extras += UInt16(teamRuns)

        if batRuns > 0 {
            let bi = try innings[idx].batterMut(striker)
            innings[idx].batters[bi].runs += UInt16(batRuns)
            innings[idx].batters[bi].balls += 1
        }

        let boi = try innings[idx].bowlerMut(bowler)
        innings[idx].bowlers[boi].runs += UInt16(bowlRuns)
        innings[idx].bowlers[boi].currentOverRuns += UInt16(bowlRuns)
        if legal { innings[idx].bowlers[boi].balls += 1 }

        let over = innings[idx].legalBalls / 6
        innings[idx].deliveries.append(DeliveryRecord(
            over: over,
            ballInOver: innings[idx].ballsInCurrentOver + (legal ? 1 : 0),
            label: "\(kind.label) \(teamRuns)",
            runs: teamRuns, isLegal: legal, isWicket: false
        ))

        if legal {
            innings[idx].legalBalls += 1
            innings[idx].ballsInCurrentOver += 1
            if (kind == .bye || kind == .legBye) && runs % 2 == 1 {
                innings[idx].swapStrike()
            }
            if innings[idx].ballsInCurrentOver >= 6 {
                if let boi = innings[idx].bowlers.firstIndex(where: { $0.playerId == bowler }) {
                    if innings[idx].bowlers[boi].currentOverRuns == 0 {
                        innings[idx].bowlers[boi].maidens += 1
                    }
                    innings[idx].bowlers[boi].currentOverRuns = 0
                }
                innings[idx].ballsInCurrentOver = 0
                innings[idx].swapStrike()
            }
        } else if (kind == .wide || kind == .noBall)
            && batRuns == 0
            && teamRuns > 1
            && (teamRuns - 1) % 2 == 1
        {
            innings[idx].swapStrike()
        }
    }

    private mutating func applyWicket(
        batterId: UUID, kind: DismissalKind, newBatterId: UUID?
    ) throws {
        guard !innings.isEmpty else { throw CricketEngineError.validation("no live innings") }
        let idx = innings.count - 1
        let bowler = innings[idx].bowlerId
        let isLegal = kind != .retired

        let bi = try innings[idx].batterMut(batterId)
        innings[idx].batters[bi].out = true
        innings[idx].batters[bi].dismissal = kind
        if isLegal { innings[idx].batters[bi].balls += 1 }

        innings[idx].wickets += 1
        if isLegal {
            innings[idx].legalBalls += 1
            innings[idx].ballsInCurrentOver += 1
            if let bid = bowler {
                let boi = try innings[idx].bowlerMut(bid)
                switch kind {
                case .bowled, .caught, .lbw, .stumped, .hitWicket:
                    innings[idx].bowlers[boi].wickets += 1
                    innings[idx].bowlers[boi].balls += 1
                default:
                    innings[idx].bowlers[boi].balls += 1
                }
            }
        }

        let score = innings[idx].runs
        let wickets = innings[idx].wickets
        let overBall = MatchState.oversBallsDisplay(innings[idx].legalBalls)
        innings[idx].fall.append(FallOfWicket(
            score: score, wickets: wickets, batterId: batterId, overBall: overBall
        ))
        innings[idx].deliveries.append(DeliveryRecord(
            over: innings[idx].legalBalls > 0 ? (innings[idx].legalBalls - 1) / 6 : 0,
            ballInOver: innings[idx].ballsInCurrentOver,
            label: "WICKET", runs: 0, isLegal: isLegal, isWicket: true
        ))

        if innings[idx].wickets >= 10
            || innings[idx].legalBalls >= UInt16(oversLimit) * 6
        {
            innings[idx].complete = true
            return
        }

        guard let newId = newBatterId else {
            throw CricketEngineError.validation("new batter required")
        }
        if !innings[idx].batters.contains(where: { $0.playerId == newId }) {
            innings[idx].batters.append(BatterStats(playerId: newId))
        }
        if innings[idx].strikerId == batterId {
            innings[idx].strikerId = newId
        } else {
            innings[idx].nonStrikerId = newId
        }

        if innings[idx].ballsInCurrentOver >= 6 {
            if let bid = bowler,
               let boi = innings[idx].bowlers.firstIndex(where: { $0.playerId == bid }) {
                if innings[idx].bowlers[boi].currentOverRuns == 0 {
                    innings[idx].bowlers[boi].maidens += 1
                }
                innings[idx].bowlers[boi].currentOverRuns = 0
            }
            innings[idx].ballsInCurrentOver = 0
            innings[idx].swapStrike()
        }
    }

    private mutating func completeInnings() throws {
        guard !innings.isEmpty else { throw CricketEngineError.validation("no innings") }
        let idx = innings.count - 1
        innings[idx].complete = true
        let innIdx = innings[idx].index
        let runs = innings[idx].runs
        if innIdx == 0 {
            target = runs + 1
            status = .inningsBreak
        } else {
            status = .complete
            finishResult()
        }
    }

    private mutating func checkAutoComplete() throws {
        guard let inn = currentInnings else { return }
        if !inn.complete {
            if inn.index >= 1, let target, inn.runs >= target {
                innings[innings.count - 1].complete = true
                status = .complete
                finishResult()
            }
            return
        }
        if inn.index == 0 && status == .live {
            target = inn.runs + 1
            status = .inningsBreak
        }
    }

    private mutating func finishResult() {
        guard innings.count >= 2 else { return }
        let a = innings[0]
        let b = innings[1]
        if b.runs > a.runs {
            winner = b.batting
            let wkts = 10 - Int(b.wickets)
            margin = "won by \(max(wkts, 0)) wickets"
        } else if b.runs < a.runs {
            winner = a.batting
            margin = "won by \(a.runs - b.runs) runs"
        } else {
            winner = nil
            margin = "tied"
        }
    }
}
