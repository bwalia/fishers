import SwiftUI

/// A running tournament: the fixture list by day, the table, and who's entered.
/// Organisers get the set-up sheet that lays out pitches and generates fixtures.
struct TournamentView: View {
    let block: FixtureBlock
    @StateObject private var store: TournamentStore
    @State private var tab: Tab = .schedule
    @State private var isSettingUp = false
    @State private var isAddingEntrants = false
    @State private var resultRow: ScheduleRow?

    enum Tab: String, CaseIterable {
        case schedule = "Schedule"
        case table = "Table"
        case entrants = "Entrants"
    }

    init(block: FixtureBlock) {
        self.block = block
        _store = StateObject(wrappedValue: TournamentStore(blockId: block.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                if let error = store.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(FishersTheme.unavailable)
                }
                switch tab {
                case .schedule: scheduleSections
                case .table: tableSections
                case .entrants: entrantSections
                }
            }
        }
        .navigationTitle(block.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isAddingEntrants = true } label: {
                        Label("Add entrants", systemImage: "person.badge.plus")
                    }
                    Button { isSettingUp = true } label: {
                        Label("Generate fixtures", systemImage: "square.grid.3x3.fill")
                    }
                    if !store.standings.isEmpty {
                        Button {
                            Task { await store.buildKnockout(perGroup: 2) }
                        } label: {
                            Label("Draw the knockout", systemImage: "trophy.fill")
                        }
                    }
                } label: {
                    if store.isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isSettingUp) {
            SetUpSheet(store: store, entrantCount: store.entrants.count)
        }
        .sheet(isPresented: $isAddingEntrants) {
            AddEntrantsSheet(store: store)
        }
        .sheet(item: $resultRow) { row in
            ResultSheet(row: row, store: store)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var scheduleSections: some View {
        if store.schedule.isEmpty && !store.isLoading {
            ContentUnavailableView(
                "No fixtures yet",
                systemImage: "square.grid.3x3",
                description: Text("Add the entrants, then generate the fixtures.")
            )
        }
        ForEach(store.scheduleByDay, id: \.day) { day in
            Section(day.day.formatted(.dateTime.weekday(.wide).day().month())) {
                ForEach(day.fixtures) { row in
                    Button {
                        resultRow = row
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.startsAt, format: .dateTime.hour().minute())
                                    .font(.caption.weight(.semibold))
                                if let court = row.courtLabel {
                                    Text(court).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 78, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.fixtureLine).font(.subheadline)
                                HStack(spacing: 6) {
                                    if let group = row.groupLabel, row.stage == "group" {
                                        Text("Group \(group)")
                                    }
                                    if row.stage == "knockout" {
                                        Text("Knockout")
                                    }
                                    if let round = row.round, row.stage == "group" {
                                        Text("R\(round)")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let score = row.scoreLine {
                                Text(score).font(.subheadline.weight(.semibold).monospacedDigit())
                            } else {
                                Image(systemName: "square.and.pencil")
                                    .font(.caption)
                                    .foregroundStyle(FishersTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tableSections: some View {
        if store.standings.isEmpty && !store.isLoading {
            ContentUnavailableView(
                "No results yet",
                systemImage: "list.number",
                description: Text("The table fills in as results are recorded.")
            )
        }
        ForEach(store.groups, id: \.self) { group in
            Section("Group \(group)") {
                ForEach(Array(store.standings(in: group).enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(standing.name).font(.subheadline)
                        Spacer()
                        Text("P\(standing.played)")
                        Text("W\(standing.won)")
                        if standing.noResult > 0 { Text("NR\(standing.noResult)") }
                        Text("\(standing.points) pts").font(.caption.weight(.bold))
                        Text(standing.difference >= 0 ? "+\(standing.difference)" : "\(standing.difference)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
        if !store.knockoutFixtures.isEmpty {
            Section("Knockout") {
                ForEach(store.knockoutFixtures) { row in
                    HStack {
                        Text(row.fixtureLine).font(.subheadline)
                        Spacer()
                        Text(row.scoreLine ?? row.startsAt.formatted(.dateTime.hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var entrantSections: some View {
        Section {
            ForEach(store.entrants) { entrant in
                HStack {
                    if let seed = entrant.seed {
                        Text("\(seed)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                    }
                    Text(entrant.name)
                        .strikethrough(entrant.withdrawn)
                    Spacer()
                    if let group = entrant.groupLabel {
                        Text("Group \(group)")
                            .font(.caption)
                            .foregroundStyle(FishersTheme.accent)
                    }
                }
            }
        } footer: {
            Text("Seeds are used to spread the strong sides across the groups.")
        }
    }
}

/// Lay out the pitches and times, then generate the fixtures into them.
private struct SetUpSheet: View {
    @ObservedObject var store: TournamentStore
    let entrantCount: Int
    @Environment(\.dismiss) private var dismiss

    @State private var courts = "Main square, Nursery ground"
    @State private var firstStart = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var matchMinutes = 150
    @State private var gapMinutes = 30
    @State private var rounds = 6
    @State private var format: TournamentFormat = .groupsKnockout
    @State private var groupCount = 2

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach([TournamentFormat.roundRobin, .groupsKnockout, .knockout], id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    if format == .groupsKnockout {
                        Stepper("Groups: \(groupCount)", value: $groupCount, in: 2...8)
                    }
                }
                Section {
                    TextField("Pitches or courts, comma separated", text: $courts)
                    DatePicker("First match", selection: $firstStart)
                    Stepper("Match length: \(matchMinutes) min", value: $matchMinutes, in: 20...480, step: 10)
                    Stepper("Gap between: \(gapMinutes) min", value: $gapMinutes, in: 0...120, step: 5)
                    Stepper("Rounds per pitch: \(rounds)", value: $rounds, in: 1...20)
                } header: {
                    Text("The grid")
                } footer: {
                    Text("\(courtList.count * rounds) slots for \(entrantCount) entrants. Anything that doesn't fit is reported rather than dropped.")
                }
            }
            .navigationTitle("Generate fixtures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        let courts = courtList
                        dismiss()
                        Task {
                            await store.setUp(
                                courts: courts, firstStart: firstStart,
                                matchMinutes: matchMinutes, gapMinutes: gapMinutes,
                                rounds: rounds, format: format, groupCount: groupCount
                            )
                        }
                    }
                    .disabled(courtList.isEmpty || entrantCount < 2)
                }
            }
        }
    }

    private var courtList: [String] {
        courts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct AddEntrantsSheet: View {
    @ObservedObject var store: TournamentStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("One club per line, strongest first", text: $text, axis: .vertical)
                        .lineLimit(6...14)
                } footer: {
                    Text("Visiting clubs don't need an account here — a name is enough. Order sets the seeding.")
                }
            }
            .navigationTitle("Add entrants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let names = text.split(separator: "\n").map(String.init)
                        dismiss()
                        Task { await store.addEntrants(names) }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ResultSheet: View {
    let row: ScheduleRow
    @ObservedObject var store: TournamentStore
    @Environment(\.dismiss) private var dismiss
    @State private var homeScore = ""
    @State private var awayScore = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(row.fixtureLine) {
                    LabeledContent(row.homeName ?? "Home") {
                        TextField("0", text: $homeScore)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(row.awayName ?? "Away") {
                        TextField("0", text: $awayScore)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let score = row.scoreLine {
                    Section("Recorded") { Text(score) }
                }
            }
            .navigationTitle("Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let home = Int(homeScore) ?? 0
                        let away = Int(awayScore) ?? 0
                        dismiss()
                        Task { await store.recordResult(row: row, homeScore: home, awayScore: away) }
                    }
                    .disabled(homeScore.isEmpty || awayScore.isEmpty)
                }
            }
            .onAppear {
                homeScore = row.homeScore.map(String.init) ?? ""
                awayScore = row.awayScore.map(String.init) ?? ""
            }
        }
    }
}
