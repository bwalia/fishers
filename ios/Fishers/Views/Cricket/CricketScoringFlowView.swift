import SwiftUI
import SwiftData

/// Setup wizard → LIVE scorer for a cricket fixture (offline-first).
struct CricketScoringFlowView: View {
    let event: Event
    let attendees: [AttendeeSummary]
    var canScore: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var store: CricketMatchStore
    @State private var step: Step = .confirm
    @State private var overs = 20
    @State private var homeName = "Home"
    @State private var awayName = "Away"
    @State private var tossWinner: MatchSide = .home
    @State private var tossDecision: TossDecision = .bat
    @State private var homeXi: [UUID] = []
    @State private var awayXi: [UUID] = []
    @State private var strikerId: UUID?
    @State private var nonStrikerId: UUID?
    @State private var bowlerId: UUID?
    @State private var message: String?
    @State private var booting = false

    enum Step: Hashable {
        case confirm, toss, xi, openers, live
    }

    init(event: Event, attendees: [AttendeeSummary], canScore: Bool) {
        self.event = event
        self.attendees = attendees
        self.canScore = canScore
        _store = StateObject(wrappedValue: CricketMatchStore(
            eventId: event.id,
            clubId: event.clubId
        ))
    }

    var body: some View {
        Group {
            switch step {
            case .confirm: confirmStep
            case .toss: tossStep
            case .xi: xiStep
            case .openers: openersStep
            case .live:
                LiveScorerView(store: store, onDone: { dismiss() })
            }
        }
        .background(FishersTheme.mist.ignoresSafeArea())
        .navigationTitle(step == .live ? "LIVE" : "Start match")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.replaceContext(modelContext) }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(event.title).font(FishersTheme.contentTitle)
            Text("Score offline on this device. Syncs when you're back online.")
                .foregroundStyle(.secondary)
            TextField("Home side", text: $homeName)
                .textFieldStyle(.roundedBorder)
            TextField("Away side", text: $awayName)
                .textFieldStyle(.roundedBorder)
            Stepper("Overs: \(overs)", value: $overs, in: 5...50)
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Spacer()
            Button {
                Task { await startMatch() }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.accent)
            .disabled(!canScore || booting)
            .accessibilityLabel("Continue to toss")
        }
        .padding()
    }

    private var tossStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Toss").font(FishersTheme.title)
            Picker("Winner", selection: $tossWinner) {
                Text(homeName).tag(MatchSide.home)
                Text(awayName).tag(MatchSide.away)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Toss winner")
            Picker("Decision", selection: $tossDecision) {
                Text("Bat").tag(TossDecision.bat)
                Text("Bowl").tag(TossDecision.bowl)
            }
            .pickerStyle(.segmented)
            Spacer()
            Button("Record toss") {
                _ = store.append(.tossRecorded(winner: tossWinner, decision: tossDecision))
                seedXiIfNeeded()
                step = .xi
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.accent)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var xiStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playing XI").font(FishersTheme.title)
            Text("Home \(homeXi.count)/11 · Away \(awayXi.count)/11")
                .foregroundStyle(.secondary)
            List {
                Section("Home — \(homeName)") {
                    ForEach(candidatePool, id: \.0) { id, name in
                        Button {
                            toggleXi(id, side: .home, name: name)
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if homeXi.contains(id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(FishersTheme.accent)
                                }
                            }
                        }
                        .accessibilityLabel("\(name), home XI")
                    }
                }
                Section("Away — \(awayName)") {
                    ForEach(candidatePool, id: \.0) { id, name in
                        Button {
                            toggleXi(id, side: .away, name: name)
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if awayXi.contains(id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(FishersTheme.accent)
                                }
                            }
                        }
                        .accessibilityLabel("\(name), away XI")
                    }
                }
            }
            .listStyle(.insetGrouped)
            Button("Confirm XIs") {
                padAndCommitXi()
                step = .openers
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.accent)
            .disabled(homeXi.count < 2 || awayXi.count < 2)
            .padding()
        }
    }

    private var openersStep: some View {
        let batting = firstInningsBatting
        let batXi = batting == .home ? homeXi : awayXi
        let bowlXi = batting == .home ? awayXi : homeXi
        return VStack(alignment: .leading, spacing: 16) {
            Text("Openers & bowler").font(FishersTheme.title)
            Text("\(store.state.name(for: batting)) to bat")
                .foregroundStyle(.secondary)
            pickerRow("Striker", selection: $strikerId, ids: batXi)
            pickerRow("Non-striker", selection: $nonStrikerId, ids: batXi)
            pickerRow("Opening bowler", selection: $bowlerId, ids: bowlXi)
            Spacer()
            Button("Start innings") {
                guard let s = strikerId, let ns = nonStrikerId, let b = bowlerId, s != ns else {
                    message = "Pick two different batters and a bowler"
                    return
                }
                _ = store.append(.inningsStarted(
                    inningsIndex: 0,
                    batting: batting,
                    strikerId: s,
                    nonStrikerId: ns,
                    bowlerId: b
                ))
                step = .live
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.accent)
            .frame(maxWidth: .infinity)
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .padding()
        .onAppear {
            if strikerId == nil { strikerId = batXi.first }
            if nonStrikerId == nil { nonStrikerId = batXi.dropFirst().first }
            if bowlerId == nil { bowlerId = bowlXi.first }
        }
    }

    private func pickerRow(_ title: String, selection: Binding<UUID?>, ids: [UUID]) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title, selection: selection) {
                Text("—").tag(UUID?.none)
                ForEach(ids, id: \.self) { id in
                    Text(store.name(for: id)).tag(UUID?.some(id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var candidatePool: [(UUID, String)] {
        var seen = Set<UUID>()
        var out: [(UUID, String)] = []
        for a in attendees {
            if seen.insert(a.userId).inserted {
                out.append((a.userId, a.name))
            }
        }
        for i in 1...22 {
            let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", i))!
            if seen.insert(id).inserted {
                out.append((id, "Player \(i)"))
            }
        }
        return out
    }

    private var firstInningsBatting: MatchSide {
        guard let winner = store.state.tossWinner, let decision = store.state.tossDecision else {
            return .home
        }
        switch decision {
        case .bat: return winner
        case .bowl: return winner.opposite
        }
    }

    private func toggleXi(_ id: UUID, side: MatchSide, name: String) {
        store.registerName(name, for: id)
        switch side {
        case .home:
            if let i = homeXi.firstIndex(of: id) { homeXi.remove(at: i) }
            else if homeXi.count < 11 { homeXi.append(id) }
        case .away:
            if let i = awayXi.firstIndex(of: id) { awayXi.remove(at: i) }
            else if awayXi.count < 11 { awayXi.append(id) }
        }
    }

    private func seedXiIfNeeded() {
        if homeXi.isEmpty {
            homeXi = Array(candidatePool.prefix(11).map(\.0))
            for (id, name) in candidatePool.prefix(11) { store.registerName(name, for: id) }
        }
        if awayXi.isEmpty {
            awayXi = Array(candidatePool.dropFirst(11).prefix(11).map(\.0))
            for (id, name) in zip(awayXi, candidatePool.dropFirst(11).prefix(11).map(\.1)) {
                store.registerName(name, for: id)
            }
        }
    }

    private func padAndCommitXi() {
        while homeXi.count < 11 {
            let id = UUID()
            homeXi.append(id)
            store.registerName("Home \(homeXi.count)", for: id)
        }
        while awayXi.count < 11 {
            let id = UUID()
            awayXi.append(id)
            store.registerName("Away \(awayXi.count)", for: id)
        }
        _ = store.append(.xiSelected(side: .home, playerIds: homeXi, captainId: homeXi.first, keeperId: nil))
        _ = store.append(.xiSelected(side: .away, playerIds: awayXi, captainId: awayXi.first, keeperId: nil))
    }

    private func startMatch() async {
        guard canScore else {
            message = "You need score permission (captain / secretary / scorer)."
            return
        }
        booting = true
        defer { booting = false }
        store.replaceContext(modelContext)
        do {
            let dto = try await FishersAPI.createCricketMatch(
                eventId: event.id,
                oversLimit: overs,
                homeName: homeName,
                awayName: awayName
            )
            _ = try await FishersAPI.claimScorer(matchId: dto.id, deviceId: store.deviceId)
            try store.loadLocalOrCreate(
                matchId: dto.id,
                homeName: homeName,
                awayName: awayName,
                oversLimit: overs
            )
            if store.state.lastSeq == 0 {
                _ = store.append(.matchPrepared(
                    oversLimit: UInt8(overs),
                    homeName: homeName,
                    awayName: awayName
                ))
            }
            switch store.state.status {
            case .live, .inningsBreak, .complete:
                step = .live
            case .ready:
                homeXi = store.state.homeXi
                awayXi = store.state.awayXi
                step = .openers
            case .selectingXi:
                step = .xi
            default:
                step = .toss
            }
        } catch {
            let localId = store.matchId ?? event.id
            do {
                try store.loadLocalOrCreate(
                    matchId: localId,
                    homeName: homeName,
                    awayName: awayName,
                    oversLimit: overs
                )
                if store.state.lastSeq == 0 {
                    _ = store.append(.matchPrepared(
                        oversLimit: UInt8(overs),
                        homeName: homeName,
                        awayName: awayName
                    ))
                }
                store.setSyncing(false, offline: true)
                step = store.state.status == .live ? .live : .toss
                message = "Working offline — will sync when online."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
