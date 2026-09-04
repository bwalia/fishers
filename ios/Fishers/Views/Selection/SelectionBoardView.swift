import SwiftUI

/// The captain's screen: who is available, who the ranking (or the assistant)
/// would pick and why, and one button to publish it to the squad.
struct SelectionBoardView: View {
    let eventId: UUID
    @StateObject private var store: SelectionStore
    @State private var isChangingStatus = false
    @State private var statusNote = ""
    @State private var newStatus = "postponed"

    init(eventId: UUID) {
        self.eventId = eventId
        _store = StateObject(wrappedValue: SelectionStore(eventId: eventId))
    }

    var body: some View {
        List {
            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(FishersTheme.unavailable)
            }
            if let board = store.board {
                header(board)
                if let proposal = store.proposal {
                    proposalSection(proposal)
                }
                squadSection(board)
                poolSection(board)
                ruledOutSection(board)
            } else if store.isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Selection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await store.suggest() }
                    } label: {
                        Label("Suggest from ranking", systemImage: "list.number")
                    }
                    if store.board?.isAssistantAvailable ?? false {
                        Button {
                            Task { await store.askAssistant() }
                        } label: {
                            Label("Let the assistant pick", systemImage: "sparkles")
                        }
                    }
                    Divider()
                    Button {
                        isChangingStatus = true
                    } label: {
                        Label("Delay or call off", systemImage: "cloud.rain.fill")
                    }
                } label: {
                    if store.isThinking {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            publishBar
        }
        .sheet(isPresented: $isChangingStatus) {
            statusSheet
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private func header(_ board: SelectionBoard) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(board.title).font(.headline)
                Text(board.startsAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(store.selected.count)/\(board.requirements.size)", systemImage: "person.3.fill")
                    Label("\(board.confirmedCount) confirmed", systemImage: "checkmark.seal.fill")
                    if board.status != "scheduled" {
                        Text(board.status.capitalized)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(FishersTheme.unavailable.opacity(0.18), in: Capsule())
                            .foregroundStyle(FishersTheme.unavailable)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = board.statusNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Players are asked to reconfirm \(board.confirmLeadHours)h before, and dropped \(board.dropLeadHours)h before if they haven't.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func proposalSection(_ proposal: SquadProposal) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    proposal.isFromAssistant ? "The assistant's side" : "The ranking's side",
                    systemImage: proposal.isFromAssistant ? "sparkles" : "list.number"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FishersTheme.accent)

                if let announcement = proposal.announcement {
                    Text(announcement).font(.callout)
                }
                if let concerns = proposal.concerns {
                    Label(concerns, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(FishersTheme.maybe)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let confidence = proposal.confidence {
                    Text("Confidence: \(confidence)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if proposal.published {
                    Label("Published to the squad", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(FishersTheme.available)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func squadSection(_ board: SelectionBoard) -> some View {
        Group {
            if !store.selected.isEmpty {
                Section("Squad") {
                    ForEach(store.selected, id: \.self) { userId in
                        if let candidate = board.candidates.first(where: { $0.userId == userId }) {
                            CandidateRow(
                                candidate: candidate,
                                reasons: board.reasons(for: userId),
                                role: .selected,
                                onTap: { store.toggle(candidate) }
                            )
                        }
                    }
                }
            }
            if !store.reserves.isEmpty {
                Section("Reserves") {
                    ForEach(store.reserves, id: \.self) { userId in
                        if let candidate = board.candidates.first(where: { $0.userId == userId }) {
                            CandidateRow(
                                candidate: candidate,
                                reasons: board.reasons(for: userId),
                                role: .reserve,
                                onTap: { store.toggle(candidate) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func poolSection(_ board: SelectionBoard) -> some View {
        let pool = board.candidates.filter {
            !store.selected.contains($0.userId)
                && !store.reserves.contains($0.userId)
                && $0.availability != .unavailable
        }
        return Section {
            ForEach(orderedByRanking(pool, board: board)) { candidate in
                CandidateRow(
                    candidate: candidate,
                    reasons: board.reasons(for: candidate.userId),
                    role: nil,
                    onTap: { store.toggle(candidate) }
                )
            }
        } header: {
            Text("Available — best first")
        } footer: {
            Text("Tap to pick. Once the squad is full, taps add reserves.")
        }
    }

    private func ruledOutSection(_ board: SelectionBoard) -> some View {
        let out = board.candidates.filter { $0.availability == .unavailable }
        return Group {
            if !out.isEmpty {
                Section("Said no") {
                    ForEach(out) { candidate in
                        HStack {
                            Text(candidate.name)
                            Spacer()
                            Text("unavailable")
                                .font(.caption)
                                .foregroundStyle(FishersTheme.unavailable)
                        }
                    }
                }
            }
        }
    }

    private func orderedByRanking(
        _ candidates: [SelectionCandidate],
        board: SelectionBoard
    ) -> [SelectionCandidate] {
        let order = board.ranked.enumerated().reduce(into: [UUID: Int]()) { $0[$1.element.userId] = $1.offset }
        return candidates.sorted { (order[$0.userId] ?? .max) < (order[$1.userId] ?? .max) }
    }

    private var publishBar: some View {
        HStack(spacing: 12) {
            Button("Save") {
                Task { await store.saveWithoutPublishing() }
            }
            .buttonStyle(.bordered)
            Button {
                Task { await store.publish() }
            } label: {
                if store.isPublishing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Publish squad").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.selected.isEmpty || store.isPublishing)
        }
        .padding()
        .background(.bar)
    }

    private var statusSheet: some View {
        NavigationStack {
            Form {
                Section("What's happening") {
                    Picker("Status", selection: $newStatus) {
                        Text("Postponed").tag("postponed")
                        Text("Cancelled").tag("cancelled")
                        Text("Back on").tag("scheduled")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("e.g. ground unplayable after Friday's rain", text: $statusNote, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Reason")
                } footer: {
                    Text("Posted to the club thread and pushed to everyone in the squad.")
                }
            }
            .navigationTitle("Delay or call off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isChangingStatus = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Announce") {
                        let status = newStatus
                        let note = statusNote.isEmpty ? nil : statusNote
                        isChangingStatus = false
                        statusNote = ""
                        Task { await store.updateStatus(status, note: note) }
                    }
                }
            }
        }
    }
}

private struct CandidateRow: View {
    let candidate: SelectionCandidate
    let reasons: [String]
    let role: SelectionState?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(candidate.name).font(.subheadline.weight(.semibold))
                        if candidate.isConfirmed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(FishersTheme.available)
                        }
                    }
                    Text(reasons.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let availability = candidate.availability {
                    Circle()
                        .fill(colour(for: availability))
                        .frame(width: 9, height: 9)
                }
                if let role {
                    Text(role == .selected ? "IN" : "RES")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (role == .selected ? FishersTheme.available : FishersTheme.maybe)
                                .opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(role == .selected ? FishersTheme.available : FishersTheme.maybe)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func colour(for status: AvailabilityStatus) -> Color {
        switch status {
        case .available: return FishersTheme.available
        case .maybe: return FishersTheme.maybe
        case .unavailable: return FishersTheme.unavailable
        }
    }
}
