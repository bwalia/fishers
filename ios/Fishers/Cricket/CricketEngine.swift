import Foundation

/// On-device cricket scoring engine — mirrors `backend/domain/src/cricket/engine.rs`.
///
/// State is a fold over the event log, so the device and the API always agree:
/// replaying the same events produces the same scorecard, undo stack included.
extension MatchState {
    /// Smallest and largest team sheet. Club cricket is not always eleven a side.
    static let minTeam = 2
    static let maxTeam = 15

    /// Rebuild from an ordered log — how a match resumes after the app is killed.
    static func replay(_ events: [ScoringEvent]) throws -> MatchState {
        var state = MatchState()
        for event in events {
            try state.apply(event)
        }
        return state
    }

    mutating func apply(_ event: ScoringEvent) throws {
        if event.seq != lastSeq + 1 && !(lastSeq == 0 && event.seq == 1) {
            if event.seq <= lastSeq { return }
            if event.seq != lastSeq + 1 {
                throw CricketEngineError.conflict("expected seq \(lastSeq + 1), got \(event.seq)")
            }
        }

        // The clock only advances for events the device stamped.
        if let at = event.at, !innings.isEmpty {
            let idx = innings.count - 1
            if innings[idx].startedAt == nil { innings[idx].startedAt = at }
            switch event.kind {
            case .deliveryRecorded, .extrasRecorded, .wicketRecorded:
                innings[idx].lastBallAt = at
            default:
                break
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
            oversLimit = max(overs, 1)
            conditions = MatchConditions.standard(overs: oversLimit)
            homeName = home
            awayName = away
            status = .preparing

        case let .conditionsProposed(proposed, by, byName):
            guard proposed.oversLimit > 0 else {
                throw CricketEngineError.validation("a match needs at least one over")
            }
            guard proposed.oversPerBowler <= proposed.oversLimit else {
                throw CricketEngineError.validation(
                    "a bowler cannot be allowed more overs than the innings has"
                )
            }
            conditions = proposed
            oversLimit = proposed.oversLimit
            conditionsProposedBy = by
            // New terms need agreeing again, by both sides.
            agreedHome = nil
            agreedAway = nil
            // The proposer has, by proposing, agreed to their own terms.
            switch by {
            case .home: agreedHome = byName
            case .away: agreedAway = byName
            }
            status = .preparing

        case let .conditionsAgreed(side, captainName):
            guard conditionsProposedBy != nil else {
                throw CricketEngineError.validation("there are no terms on the table to agree to")
            }
            switch side {
            case .home: agreedHome = captainName
            case .away: agreedAway = captainName
            }
            if conditionsAgreed { status = .toss }

        case let .officialsAppointed(appointed):
            for official in appointed.umpires + appointed.scorers {
                setName(official.name, for: official.id)
            }
            officials = appointed

        case let .playerOfTheMatch(playerId):
            playerOfTheMatch = playerId

        case let .penaltyRuns(runs, reason, toSide):
            guard runs > 0 else {
                throw CricketEngineError.validation("a penalty is at least one run")
            }
            _ = reason // carried in the log for the commentary to read

            // Default to whoever is batting: that is the common award.
            guard let side = toSide ?? currentInnings?.batting else {
                throw CricketEngineError.validation("no live innings")
            }

            // The side may not have batted yet, in which case the runs wait and
            // open their innings.
            guard let idx = innings.lastIndex(where: { $0.batting == side }) else {
                pendingPenalties[side.rawValue, default: 0] += UInt16(runs)
                lastSeq = event.seq
                return
            }

            let isCurrent = idx == innings.count - 1
            innings[idx].runs += UInt16(runs)
            innings[idx].extras += UInt16(runs)
            innings[idx].penalties += UInt16(runs)
            innings[idx].penaltyRunsAwarded += UInt16(runs)
            if isCurrent {
                innings[idx].partnershipRuns += UInt16(runs)
                innings[idx].deliveries.append(DeliveryRecord(
                    over: innings[idx].legalBalls / 6,
                    ballInOver: innings[idx].ballsInCurrentOver,
                    label: "\(runs)p",
                    runs: runs, isLegal: false, isWicket: false
                ))
            }

        case let .fieldSet(outsideCircle, behindSquareLeg):
            guard !innings.isEmpty else {
                throw CricketEngineError.validation("no live innings")
            }
            let idx = innings.count - 1
            innings[idx].fieldersOutside = outsideCircle
            innings[idx].fieldersBehindSquareLeg = behindSquareLeg

        case let .batterResumed(batterId, replacingId):
            guard !innings.isEmpty else { throw CricketEngineError.validation("no innings") }
            let idx = innings.count - 1
            let bi = try innings[idx].batterIndex(batterId)
            guard innings[idx].batters[bi].canResume else {
                throw CricketEngineError.validation(
                    "only a batter who retired hurt can come back"
                )
            }
            innings[idx].batters[bi].retiredHurt = false
            if let out = replacingId, innings[idx].strikerId == out {
                innings[idx].strikerId = batterId
            } else if let out = replacingId, innings[idx].nonStrikerId == out {
                innings[idx].nonStrikerId = batterId
            } else if innings[idx].strikerId == nil {
                innings[idx].strikerId = batterId
            } else if innings[idx].nonStrikerId == nil {
                innings[idx].nonStrikerId = batterId
            } else {
                throw CricketEngineError.validation("say which batter they are coming in for")
            }

        case let .tossRecorded(winner, decision):
            guard conditionsAgreed else {
                throw CricketEngineError.validation(
                    "both captains have to agree the overs, ground and ball first"
                )
            }
            tossWinner = winner
            tossDecision = decision
            status = .selectingXi

        case let .xiSelected(side, players, captainId, keeperId):
            guard players.count >= Self.minTeam, players.count <= Self.maxTeam else {
                throw CricketEngineError.validation(
                    "a team sheet is \(Self.minTeam)–\(Self.maxTeam) players, got \(players.count)"
                )
            }
            for player in players {
                setName(player.name, for: player.id)
                setBatsLeft(player.batsLeft, for: player.id)
            }
            let ids = players.map(\.id)
            switch side {
            case .home:
                homeXi = ids; homeCaptain = captainId; homeKeeper = keeperId
            case .away:
                awayXi = ids; awayCaptain = captainId; awayKeeper = keeperId
            }
            if homeXi.count >= Self.minTeam && awayXi.count >= Self.minTeam {
                status = .ready
            }

        case let .inningsStarted(idx, batting, striker, non, bowler, superOver):
            guard striker != non else {
                throw CricketEngineError.validation("the two openers must be different players")
            }
            // Both captains have to have named a side. Nothing enforced this,
            // so a match could start with one team sheet in and the other
            // side's batters invented as they came to the crease.
            guard !homeXi.isEmpty, !awayXi.isEmpty else {
                throw CricketEngineError.validation(
                    "both sides need a team sheet before the first ball"
                )
            }
            var batters = xi(batting).map { BatterStats(playerId: $0) }
            for id in [striker, non] where !batters.contains(where: { $0.playerId == id }) {
                batters.append(BatterStats(playerId: id))
            }
            var inn = InningsState(index: idx, batting: batting, bowling: batting.opposite)
            inn.batters = batters
            inn.strikerId = striker
            inn.nonStrikerId = non
            inn.bowlerId = bowler
            // A super over is one over and two wickets, whatever the match is.
            inn.wicketsAllowed = superOver ? 2 : UInt8(min(max(batters.count - 1, 1), 10))
            inn.oversAvailable = superOver ? 1 : max(conditions.oversLimit, oversLimit)
            inn.superOver = superOver
            inn.powerplayOvers = superOver ? 0 : conditions.powerplayOvers
            inn.ensureBowler(bowler)
            // Penalties awarded before this side batted open their innings.
            let waiting = pendingPenalties.removeValue(forKey: batting.rawValue) ?? 0
            if waiting > 0 {
                inn.runs += waiting
                inn.extras += waiting
                inn.penalties += waiting
                inn.penaltyRunsAwarded += waiting
            }
            innings.append(inn)
            status = .live
            if superOver {
                // A tie is no longer the result; the super over decides it.
                winner = nil
                margin = nil
                superOvers = UInt8(max(0, innings.count - 2) / 2 + 1)
            }
            // The opening bowler counts against the allocation like any other.
            try checkBowlerAvailable(bowler)
            // Every odd innings is a chase of the one before it.
            if idx % 2 == 1, innings.count >= 2 {
                target = innings[innings.count - 2].runs + 1
            }

        case let .deliveryRecorded(runs, isLegal, four, six, shot):
            try applyDelivery(runs: runs, isLegal: isLegal, four: four, six: six, shot: shot)

        case let .extrasRecorded(kind, runs, boundary, offTheBat, shot):
            try applyExtras(
                kind: kind, runs: runs, boundary: boundary,
                offTheBat: offTheBat, shot: shot
            )

        case let .oversRevised(inningsIndex, overs):
            let overs = max(overs, 1)
            let idx = Int(inningsIndex)
            guard idx < innings.count else {
                throw CricketEngineError.validation("no such innings")
            }
            let bowled = UInt8((Int(innings[idx].legalBalls) + 5) / 6)
            guard overs >= bowled else {
                throw CricketEngineError.validation("\(bowled) overs have already been bowled")
            }
            innings[idx].oversAvailable = overs
            closeIfFinished(idx)

        case let .wicketRecorded(batterId, kind, fielderId, newBatterId, runs, onExtra):
            try applyWicket(
                batterId: batterId, kind: kind, fielderId: fielderId,
                newBatterId: newBatterId, runs: runs, onExtra: onExtra
            )

        case let .bowlerChanged(bowlerId):
            guard !innings.isEmpty else { throw CricketEngineError.validation("no innings") }
            try checkBowlerAvailable(bowlerId)
            let idx = innings.count - 1
            innings[idx].ensureBowler(bowlerId)
            innings[idx].bowlerId = bowlerId
            innings[idx].ballsInCurrentOver = 0

        case .inningsCompleted:
            try completeInnings()

        case let .matchCompleted(winner, margin):
            self.winner = winner
            self.margin = margin
            status = .complete

        case let .matchAbandoned(reason):
            guard status != .complete else {
                throw CricketEngineError.conflict("this match already has a result")
            }
            let trimmed = reason.trimmingCharacters(in: .whitespaces)
            winner = nil
            margin = trimmed.isEmpty
                ? "Abandoned — no result"
                : "Abandoned — \(trimmed) (no result)"
            abandoned = true
            status = .complete

        case .undoLast:
            break
        }

        lastSeq = event.seq
        checkAutoComplete()
    }

    /// Two Laws and one agreement: nobody bowls consecutive overs, nobody
    /// exceeds the allocation the captains settled, and a side with a single
    /// bowler is excused the first of those.
    /// The same bowler carrying straight on into the next over.
    ///
    /// `checkBowlerAvailable` only ran when a scorer explicitly changed bowler,
    /// so simply not changing one bowled the whole innings with one man —
    /// legal-looking, and against the Laws. Checked at the first ball of an
    /// over; mid-over the bowler is of course unchanged.
    private func checkNewOverBowler() throws {
        guard let inn = innings.last, !inn.complete else { return }
        guard inn.ballsInCurrentOver == 0, let bowler = inn.bowlerId else { return }
        if inn.lastOverBowler == bowler && xi(inn.bowling).count > 1 {
            throw CricketEngineError.validation(
                "\(name(for: bowler)) bowled the last over — change the bowler before the next one"
            )
        }
    }

    private func checkBowlerAvailable(_ bowler: UUID) throws {
        guard let inn = currentInnings else { return }
        if inn.lastOverBowler == bowler && xi(inn.bowling).count > 1 {
            throw CricketEngineError.validation(
                "\(name(for: bowler)) bowled the last over — nobody bowls two in a row"
            )
        }
        if conditions.oversPerBowler > 0 {
            let bowled = inn.bowlers.first { $0.playerId == bowler }.map { UInt8($0.balls / 6) } ?? 0
            if bowled >= conditions.oversPerBowler {
                throw CricketEngineError.validation(
                    "\(name(for: bowler)) has bowled their \(conditions.oversPerBowler) overs"
                )
            }
        }
    }

    // MARK: - Undo

    private mutating func pushHistory() {
        history.append(MatchStateSnapshot(
            status: status, innings: innings, target: target, winner: winner,
            margin: margin, playerOfTheMatch: playerOfTheMatch, superOvers: superOvers,
            pendingPenalties: pendingPenalties
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
        playerOfTheMatch = snap.playerOfTheMatch
        superOvers = snap.superOvers
        pendingPenalties = snap.pendingPenalties
    }

    // MARK: - Scoring

    private mutating func applyDelivery(
        runs: UInt8, isLegal: Bool, four: Bool, six: Bool, shot: ShotRecord?
    ) throws {
        try checkNewOverBowler()
        guard !innings.isEmpty else { throw CricketEngineError.validation("no live innings") }
        let idx = innings.count - 1
        guard !innings[idx].complete else {
            throw CricketEngineError.validation("innings complete")
        }
        guard let striker = innings[idx].strikerId else {
            throw CricketEngineError.validation("no striker")
        }
        guard let bowler = innings[idx].bowlerId else {
            throw CricketEngineError.validation("no bowler")
        }

        innings[idx].runs += UInt16(runs)
        innings[idx].partnershipRuns += UInt16(runs)

        let bi = try innings[idx].batterIndex(striker)
        innings[idx].batters[bi].runs += UInt16(runs)
        if isLegal { innings[idx].batters[bi].balls += 1 }
        if four { innings[idx].batters[bi].fours += 1 }
        if six { innings[idx].batters[bi].sixes += 1 }

        let boi = try innings[idx].bowlerIndex(bowler)
        innings[idx].bowlers[boi].runs += UInt16(runs)
        innings[idx].bowlers[boi].currentOverRuns += UInt16(runs)
        if isLegal { innings[idx].bowlers[boi].balls += 1 }

        let label = six ? "6" : (four ? "4" : "\(runs)")
        let over = innings[idx].legalBalls / 6
        let ballIn = innings[idx].ballsInCurrentOver + (isLegal ? 1 : 0)
        innings[idx].deliveries.append(DeliveryRecord(
            over: over, ballInOver: ballIn, label: label,
            runs: runs, isLegal: isLegal, isWicket: false,
            batterId: striker, bowlerId: bowler, shot: shot
        ))

        if isLegal {
            innings[idx].legalBalls += 1
            innings[idx].ballsInCurrentOver += 1
            innings[idx].partnershipBalls += 1
            // A free hit lasts one legal delivery.
            innings[idx].freeHit = false
            if runs % 2 == 1 { innings[idx].swapStrike() }
            completeOverIfDue(idx, bowler: bowler)
        }
        closeIfFinished(idx)
    }

    /// An extra, plus whatever the ball did afterwards.
    ///
    /// `runs` is what the batters ran (or the boundary), *on top of* the one-run
    /// penalty a wide or a no ball carries. The three things that have to come
    /// apart are what the side scores, what the batter is credited with, and
    /// what the bowler is charged.
    private mutating func applyExtras(
        kind: ExtraKind, runs: UInt8, boundary: Bool, offTheBat: Bool, shot: ShotRecord?
    ) throws {
        try checkNewOverBowler()
        guard !innings.isEmpty else { throw CricketEngineError.validation("no live innings") }
        let idx = innings.count - 1
        guard !innings[idx].complete else {
            throw CricketEngineError.validation("innings complete")
        }
        guard let bowler = innings[idx].bowlerId else {
            throw CricketEngineError.validation("no bowler")
        }
        guard let striker = innings[idx].strikerId else {
            throw CricketEngineError.validation("no striker")
        }

        let penalty: UInt8 = (kind == .wide || kind == .noBall) ? 1 : 0
        let legal = (kind == .bye || kind == .legBye)
        let batRuns: UInt8 = (kind == .noBall && offTheBat) ? runs : 0
        let teamRuns = penalty + runs
        let extraRuns = teamRuns >= batRuns ? teamRuns - batRuns : 0
        let bowlerRuns: UInt8
        switch kind {
        case .wide: bowlerRuns = penalty + runs
        case .noBall: bowlerRuns = penalty + batRuns
        case .bye, .legBye, .penalty: bowlerRuns = 0
        }

        innings[idx].runs += UInt16(teamRuns)
        innings[idx].extras += UInt16(extraRuns)
        innings[idx].partnershipRuns += UInt16(teamRuns)
        switch kind {
        case .wide:
            innings[idx].wides += UInt16(extraRuns)
        case .noBall:
            innings[idx].noBalls += UInt16(penalty)
            if !offTheBat { innings[idx].byes += UInt16(runs) }
        case .bye:
            innings[idx].byes += UInt16(extraRuns)
        case .legBye:
            innings[idx].legByes += UInt16(extraRuns)
        case .penalty:
            innings[idx].penalties += UInt16(extraRuns)
        }

        // The batter faces a no ball, a bye and a leg bye; never a wide.
        if kind != .wide && kind != .penalty {
            let bi = try innings[idx].batterIndex(striker)
            innings[idx].batters[bi].balls += 1
            if batRuns > 0 {
                innings[idx].batters[bi].runs += UInt16(batRuns)
                if boundary && batRuns >= 6 {
                    innings[idx].batters[bi].sixes += 1
                } else if boundary && batRuns >= 4 {
                    innings[idx].batters[bi].fours += 1
                }
            }
        }

        let boi = try innings[idx].bowlerIndex(bowler)
        innings[idx].bowlers[boi].runs += UInt16(bowlerRuns)
        innings[idx].bowlers[boi].currentOverRuns += UInt16(bowlerRuns)
        if legal { innings[idx].bowlers[boi].balls += 1 }
        switch kind {
        case .wide: innings[idx].bowlers[boi].wides += 1
        case .noBall: innings[idx].bowlers[boi].noBalls += 1
        default: break
        }

        let label: String
        switch kind {
        case .wide: label = runs > 0 ? "wd+\(runs)" : "wd"
        case .noBall: label = runs > 0 ? "nb+\(runs)" : "nb"
        case .bye: label = "\(runs)b"
        case .legBye: label = "\(runs)lb"
        case .penalty: label = "\(runs)p"
        }
        let over = innings[idx].legalBalls / 6
        let ballIn = innings[idx].ballsInCurrentOver + (legal ? 1 : 0)
        innings[idx].deliveries.append(DeliveryRecord(
            over: over, ballInOver: ballIn, label: label,
            runs: teamRuns, isLegal: legal, isWicket: false,
            batterId: striker, bowlerId: bowler, shot: shot
        ))

        if legal {
            innings[idx].legalBalls += 1
            innings[idx].ballsInCurrentOver += 1
            innings[idx].partnershipBalls += 1
            innings[idx].freeHit = false
        }
        // A no ball buys the batter a free hit off the next legal delivery.
        if kind == .noBall { innings[idx].freeHit = true }
        // Whatever they ran, an odd number puts the other batter on strike —
        // and a boundary is four or six, so it never does.
        if runs % 2 == 1 && !boundary {
            innings[idx].swapStrike()
        }
        if legal {
            completeOverIfDue(idx, bowler: bowler)
        }
        closeIfFinished(idx)
    }

    private mutating func applyWicket(
        batterId: UUID, kind: DismissalKind, fielderId: UUID?,
        newBatterId: UUID?, runs: UInt8, onExtra: Bool
    ) throws {
        // A wicket uses a ball, so it can open an over. Retiring does not,
        // and `onExtra` means the ball was already counted.
        if kind.usesABall && !onExtra { try checkNewOverBowler() }
        guard !innings.isEmpty else { throw CricketEngineError.validation("no live innings") }
        let idx = innings.count - 1
        guard !innings[idx].complete else {
            throw CricketEngineError.validation("innings complete")
        }
        let bowler = innings[idx].bowlerId
        let striker = innings[idx].strikerId
        if innings[idx].freeHit && !kind.allowedOnAFreeHit {
            throw CricketEngineError.validation("it is a free hit — only a run out can get them")
        }
        // A dismissal on a delivery already booked as an extra must not count
        // the ball a second time.
        let isLegal = kind.usesABall && !onExtra
        let countsAWicket = kind.costsAWicket

        // Runs completed before the dismissal — a run out is usually off the bat.
        if runs > 0, let strikerId = striker {
            innings[idx].runs += UInt16(runs)
            innings[idx].partnershipRuns += UInt16(runs)
            let bi = try innings[idx].batterIndex(strikerId)
            innings[idx].batters[bi].runs += UInt16(runs)
            if let bid = bowler {
                let boi = try innings[idx].bowlerIndex(bid)
                innings[idx].bowlers[boi].runs += UInt16(runs)
                innings[idx].bowlers[boi].currentOverRuns += UInt16(runs)
            }
        }

        let outIndex = try innings[idx].batterIndex(batterId)
        if countsAWicket {
            innings[idx].batters[outIndex].out = true
        } else {
            // Retired hurt: off the field, but not out, and may resume.
            innings[idx].batters[outIndex].retiredHurt = true
        }
        innings[idx].batters[outIndex].dismissal = kind
        innings[idx].batters[outIndex].fielderId = fielderId
        innings[idx].batters[outIndex].bowlerId = kind.creditsBowler ? bowler : nil

        // The ball is faced by whoever was on strike, not necessarily the batter
        // given out — a non-striker can be run out.
        if isLegal, let strikerId = striker {
            let bi = try innings[idx].batterIndex(strikerId)
            innings[idx].batters[bi].balls += 1
        }

        if countsAWicket { innings[idx].wickets += 1 }
        if isLegal {
            innings[idx].legalBalls += 1
            innings[idx].ballsInCurrentOver += 1
            innings[idx].partnershipBalls += 1
            innings[idx].freeHit = false
            if let bid = bowler {
                let boi = try innings[idx].bowlerIndex(bid)
                innings[idx].bowlers[boi].balls += 1
            }
        }
        // The wicket is the bowler's whether or not the delivery counted — a
        // stumping off a wide is still theirs.
        if kind.creditsBowler, let bid = bowler {
            let boi = try innings[idx].bowlerIndex(bid)
            innings[idx].bowlers[boi].wickets += 1
        }

        if countsAWicket {
            innings[idx].fall.append(FallOfWicket(
                score: innings[idx].runs,
                wickets: innings[idx].wickets,
                batterId: batterId,
                overBall: MatchState.oversBallsDisplay(innings[idx].legalBalls),
                partnershipRuns: innings[idx].partnershipRuns,
                partnershipBalls: innings[idx].partnershipBalls
            ))
            innings[idx].partnershipRuns = 0
            innings[idx].partnershipBalls = 0
        }

        let over = innings[idx].legalBalls > 0 ? (innings[idx].legalBalls - 1) / 6 : 0
        innings[idx].deliveries.append(DeliveryRecord(
            over: over,
            ballInOver: innings[idx].ballsInCurrentOver,
            label: !countsAWicket ? "RH" : (runs > 0 ? "\(runs)W" : "W"),
            runs: runs, isLegal: isLegal, isWicket: countsAWicket,
            batterId: striker, bowlerId: bowler, shot: nil
        ))

        // Batters cross on odd completed runs, so settle the ends before the
        // replacement takes the dismissed player's place.
        if isLegal && runs % 2 == 1 { innings[idx].swapStrike() }

        let outOfOvers = innings[idx].ballsAllowed.map { innings[idx].legalBalls >= $0 } ?? false
        if innings[idx].isAllOut || outOfOvers {
            innings[idx].complete = true
            return
        }

        guard let newId = newBatterId else {
            throw CricketEngineError.validation("new batter required")
        }
        if let existing = innings[idx].batters.firstIndex(where: { $0.playerId == newId }) {
            // Someone who retired hurt and is coming back in.
            innings[idx].batters[existing].retiredHurt = false
        } else {
            innings[idx].batters.append(BatterStats(playerId: newId))
        }
        if innings[idx].strikerId == batterId {
            innings[idx].strikerId = newId
        } else if innings[idx].nonStrikerId == batterId {
            innings[idx].nonStrikerId = newId
        } else {
            innings[idx].strikerId = newId
        }

        completeOverIfDue(idx, bowler: bowler)
    }

    // MARK: - Innings and result

    private mutating func completeInnings() throws {
        guard !innings.isEmpty else { throw CricketEngineError.validation("no innings") }
        let idx = innings.count - 1
        innings[idx].complete = true
        if innings[idx].index == 0 {
            target = innings[idx].runs + 1
            status = .inningsBreak
        } else {
            status = .complete
            finishResult()
        }
    }

    private mutating func checkAutoComplete() {
        guard let inn = currentInnings else { return }
        if !inn.complete {
            if inn.index % 2 == 1, let target, inn.runs >= target {
                innings[innings.count - 1].complete = true
                status = .complete
                finishResult()
            }
            return
        }
        if inn.index % 2 == 0 && status == .live {
            target = inn.runs + 1
            status = .inningsBreak
        } else if inn.index % 2 == 1 && status != .complete {
            status = .complete
            finishResult()
        }
    }

    /// Six legal balls: bank the maiden, reset the count, change ends.
    private mutating func completeOverIfDue(_ idx: Int, bowler: UUID?) {
        guard innings[idx].ballsInCurrentOver >= 6 else { return }
        if let bowler,
           let boi = innings[idx].bowlers.firstIndex(where: { $0.playerId == bowler }) {
            if innings[idx].bowlers[boi].currentOverRuns == 0 {
                innings[idx].bowlers[boi].maidens += 1
            }
            innings[idx].bowlers[boi].currentOverRuns = 0
        }
        innings[idx].lastOverBowler = bowler
        innings[idx].ballsInCurrentOver = 0
        innings[idx].swapStrike()
    }

    private mutating func closeIfFinished(_ idx: Int) {
        let outOfOvers = innings[idx].ballsAllowed.map { innings[idx].legalBalls >= $0 } ?? false
        if outOfOvers || innings[idx].isAllOut {
            innings[idx].complete = true
        }
    }

    /// The result comes from the last pair of innings, so a super over decides
    /// a match that the regular innings tied.
    private mutating func finishResult() {
        guard innings.count >= 2 else { return }
        let first = innings[innings.count - 2]
        let second = innings[innings.count - 1]
        let isSuperOver = second.superOver
        let decider = isSuperOver ? " the super over" : ""

        if second.runs > first.runs {
            let wickets = second.wicketsAllowed > second.wickets
                ? second.wicketsAllowed - second.wickets : 0
            let total = UInt16(second.oversAvailable) * 6
            let ballsLeft = total > second.legalBalls ? total - second.legalBalls : 0
            var text = "\(name(for: second.batting)) won\(decider) by \(wickets) wicket\(wickets == 1 ? "" : "s")"
            if ballsLeft > 0 && !isSuperOver { text += " (\(ballsLeft) balls remaining)" }
            winner = second.batting
            margin = text
        } else if second.runs < first.runs {
            let runs = first.runs - second.runs
            winner = first.batting
            margin = "\(name(for: first.batting)) won\(decider) by \(runs) run\(runs == 1 ? "" : "s")"
        } else {
            winner = nil
            margin = isSuperOver ? "Super over tied" : "Match tied"
        }
    }
}
