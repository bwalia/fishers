import XCTest

/// What the video tour says, and the markers that put each line against the right second of
/// footage.
///
/// `scripts/record-tour-video.sh` records the Simulator while `FishersTourUITests` runs, then
/// reads these markers back out of the result bundle and hands them to `scripts/tour-video.swift`,
/// which captions the recording. Every line is stamped at the moment the screen it describes had
/// settled, so nothing has to be lined up by hand afterwards.
///
/// The captions describe the seeded season by club and by player, never by id or reference:
/// those change every time the season is seeded again.
enum TourNarration {
    /// One line per screenshot the tour takes, keyed by its name. A screenshot with no line here
    /// is still captured; the film simply keeps the previous caption up.
    static let captions: [String: String] = [
        // 1 — Joining a club
        "onb-01-welcome": "Fishers is club cricket on a phone: fixtures, availability, selection and the scorebook. This is a player opening it for the first time.",
        "onb-02-signup": "Signing up asks one thing first — whether you run a club or play for one. The app is a different shape for each.",
        "onb-03-quickstart": "The quick start is a sport and a mobile number. Everything else about a player can wait until they have been picked once.",
        "onb-04-confirm": "A club is somebody's real membership list, so an address gets confirmed before it can join one. The code arrives by email.",
        "onb-05-profile-link": "New players are not searched for; they hand over a link. This one goes in the club's WhatsApp group, and the secretary invites them from it.",
        "onb-06-home-waiting": "Home before a club: the profile is part filled, and there is nothing in the diary yet.",
        "onb-07-invite-arrives": "The secretary sends the invite from that link, and it is waiting on Home — no code to type in, no email to go and find.",
        "onb-08-invite-accepted": "Accepted, and the club's season is theirs: fixtures, the squad, the chat and the scores.",
        "onb-09-profile-strength": "The profile keeps a score of itself. What is missing is what a captain looks at when picking, so the app says which line to fill in next.",
        "onb-10-profile-cricket": "A cricketer's profile: where they bat, what they bowl, the standard they play and how far they will travel.",

        // 2 — Can you play on Saturday?
        "avail-01-fixtures": "The Fixtures tab is every fixture of every club you are in, each asking the one thing it needs: can you play?",
        "avail-02-answer": "Three taps — available, maybe, can't play. The answer is saved as it is tapped and the captain sees it immediately.",
        "avail-03-answered": "It says what you said, and it can be changed until the side goes up.",
        "avail-04-calendar": "The calendar is the other way round: mark the Saturdays you are away and every fixture on them is answered at once.",
        "avail-05-marked": "A weekend away marked once, rather than a message to the captain for each game.",
        "avail-06-usual-days": "And the days you usually play, so the season starts from your own pattern rather than from nothing.",
        "avail-07-event": "Inside a fixture: where, when, the match fee, and who else has said yes.",

        // 3 — The captain picks the side
        "sel-01-board": "The captain's selection board for Saturday. Everyone who could play, in one list.",
        "sel-02-signals": "Beside each name: what they said, what the calendar says, and how reliably they turn up when they are picked.",
        "sel-03-suggested": "The assistant can suggest a side from availability, reliability and who has been left out lately. The captain is the one who picks.",
        "sel-04-picked": "Eleven picked and two down as reserves, in batting order.",
        "sel-05-publish": "Publishing tells everybody at once.",
        "sel-06-announced": "The squad lands in the club chat, where the rest of the week's arrangements already are.",
        "sel-07-confirm": "The players picked confirm their place. Anyone who has not confirmed by the deadline loses it to a reserve, and the app does that itself.",

        // 4 — A T20, ball by ball
        "t20-01-fixture": "Tonight's fixture: a floodlit T20, twenty overs a side. The captain has the book.",
        "t20-02-terms": "Before a ball: the terms both captains settle at the toss. Twenty overs, four an over each, a six-over powerplay, white ball.",
        "t20-03-agreed": "One captain proposes and the other agrees, each against their own name. There is no toss until both have.",
        "t20-04-toss": "The toss, recorded before the team sheets, the way it happens.",
        "t20-05-sheet": "The team sheet is picked from the club's squad, in batting order, with the captain and the keeper marked.",
        "t20-06-openers": "Openers and the bowler to start. From here the app is a scorebook.",
        "t20-07-first-over": "One tap a ball. The score, the two batters, the bowler's figures and this over so far.",
        "t20-08-boundary": "A boundary asks where it went. The field mirrors for a left-hander, so 'driven through cover' is right for both.",
        "t20-09-powerplay": "The powerplay is on the screen while it lasts, with the overs left in it.",
        "t20-10-wicket": "A wicket takes the bowler's name, the fielder's, and who is in next.",
        "t20-11-extras": "Extras are the arithmetic the app does rather than the scorer: a wide they ran a single off is two runs, and both of them wides.",
        "t20-12-free-hit": "A no ball sets a free hit. While it stands, only a run out can get the batter, and the sheet offers nothing else.",
        "t20-13-bowler-gate": "Nobody bowls two overs in a row and nobody bowls more than their four, so at the end of an over the app asks who is next — and says who cannot.",
        "t20-14-innings-break": "Twenty overs bowled. The innings closes itself.",
        "t20-15-target": "The chase, with the target, the rate it needs and the Duckworth–Lewis–Stern par beside it in case the rain comes.",
        "t20-16-last-over": "Last over, and the arithmetic every fielding side is doing in its head.",
        "t20-17-result": "The result, from the log rather than from anyone's addition.",
        "t20-18-potm": "Player of the match, and the game is finished.",
        "t20-19-scorecard": "The full card: every batter, every bowler, the extras and the fall of wickets.",

        // 5 — The rest of the cricket
        "ckt-01-wagon-wheel": "The wagon wheel is built from the same balls — every scoring shot, where it went and what the stroke was.",
        "ckt-02-commentary": "And a commentary, written from the log rather than typed by anybody: over, bowler, batter, what happened.",
        "ckt-03-share": "The live scoreboard is a link. Anyone with it follows the match ball by ball without an account — parents, the opposition, the club bar.",
        "ckt-04-scores": "Every match the club has played or is playing, live and finished.",
        "ckt-05-result": "A finished league match from earlier in the season, with its own card kept the same way.",
        "ckt-06-club-stats": "The club's season, folded up out of those cards: runs, wickets, catches — nobody types this in.",
        "ckt-07-career": "A player's own figures, and the record they are building across seasons.",
        "ckt-08-public-page": "The club's public page — record, top players and next fixtures — for anyone who has heard of the club and has no account.",
        "ckt-09-qr": "Every club and team has a QR code. At the toss the other captain scans it, and the scorecard knows who they are without anyone spelling a name.",
        "ckt-10-live-match": "The 2nd XI are playing at the same time, scored on somebody else's phone. Everyone in the club sees it move.",
        "ckt-11-scorer-menu": "What else the book can do: correct a ball three back, set the field, add penalty runs, cut the overs for rain, or hand the book to somebody else.",
        "ckt-12-handover": "One person scores at a time. The book moves when they pass it on, and the trail keeps who had it when.",
        "ckt-13-correction": "Scorers get it wrong three balls back, not just on the last one. Pick the ball and the innings winds back to it — recorded, not erased.",
        "ckt-14-home": "All of it lands back on Home: what is in progress, what is next, and what the club needs from you this week.",
    ]

    // MARK: Markers

    /// True when the run is being recorded for the film, which slows the tour down so each caption
    /// can be read.
    static var isVideoRun: Bool { ProcessInfo.processInfo.environment["TOUR_VIDEO"] == "1" }

    private nonisolated(unsafe) static var markers: [[String: Any]] = []
    private nonisolated(unsafe) static var openChapter = false

    private static func emit(_ marker: [String: Any]) {
        markers.append(marker)
        if let data = try? JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print("TOURMARK \(line)")
        }
    }

    /// Opens a chapter of the film, closing the one before it. Footage between chapters — the app
    /// relaunching, an account being signed in — is cut out.
    static func chapter(_ title: String, _ subtitle: String) {
        if openChapter { chapterEnd() }
        openChapter = true
        emit(["kind": "section", "at": Date().timeIntervalSince1970, "title": title, "subtitle": subtitle])
    }

    static func chapterEnd() {
        guard openChapter else { return }
        openChapter = false
        emit(["kind": "sectionEnd", "at": Date().timeIntervalSince1970])
    }

    /// Drops a stretch of the recording from the film: the middle overs of an innings, say, where
    /// the tour has to tap every ball but nobody needs to watch it. The caption either side of it
    /// stays as it was.
    static func cut(from: Date, to: Date = Date()) {
        emit(["kind": "cut", "from": from.timeIntervalSince1970, "to": to.timeIntervalSince1970])
    }

    /// Marks the moment a screen described by `captions[id]` was on screen and settled.
    static func beat(_ id: String) {
        guard let text = captions[id] else { return }
        emit(["kind": "beat", "at": Date().timeIntervalSince1970, "id": id, "text": text])
    }

    /// How long to hold a screen so its caption can be read.
    static func readingSeconds(for id: String) -> TimeInterval {
        guard isVideoRun, let text = captions[id] else { return 0 }
        let words = text.split(separator: " ").count
        return min(9, max(2.6, 1.1 + Double(words) * 0.34))
    }

    /// Everything the run marked, as the recorder reads it back out of the result bundle.
    /// Attached rather than only printed: xcodebuild's log interleaves and truncates, a result
    /// bundle attachment does not.
    static func attach(to testCase: XCTestCase) {
        chapterEnd()
        guard !markers.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: markers, options: [.sortedKeys])
        else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "tour-markers"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
        markers.removeAll()
    }
}
