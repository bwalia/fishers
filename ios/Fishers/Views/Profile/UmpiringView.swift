import SwiftUI

/// Somebody's umpiring record.
///
/// One view for your own page and for somebody else's, because they are the
/// same record — the difference is whether the willingness is a toggle or a
/// badge.
struct UmpiringView: View {
    /// nil is "mine".
    var userId: UUID?
    var name: String?

    @State private var profile: UmpireProfile?
    @State private var error: String?
    @State private var saving = false
    @State private var editingNote = false
    @State private var note = ""

    private var isMine: Bool { userId == nil }

    var body: some View {
        Group {
            if let profile {
                content(profile)
            } else if let error {
                Text(error).foregroundStyle(FishersTheme.unavailable)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ p: UmpireProfile) -> some View {
        Section {
            HStack(spacing: FishersTheme.space3) {
                figure("\(p.matches)", p.matches == 1 ? "match umpired" : "matches umpired")
                figure(p.ratingAverage.map { String(format: "%.1f", $0) } ?? "—", p.ratingLine)
            }

            if isMine {
                Toggle("I umpire", isOn: Binding(
                    get: { p.umpires },
                    set: { on in Task { await save(umpires: on) } }
                ))
                .disabled(saving)

                if p.umpires {
                    if editingNote {
                        TextField("Level 1 ECB · club matches only", text: $note)
                            .textInputAutocapitalization(.sentences)
                        HStack {
                            Button("Save") {
                                Task { await save(note: .some(note.trimmed.isEmpty ? nil : note.trimmed)) }
                            }
                            .disabled(saving)
                            Button("Cancel") { editingNote = false }
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(p.note == nil ? "Add a note for captains" : "Edit note") {
                            note = p.note ?? ""
                            editingNote = true
                        }
                    }
                }
            } else if p.umpires {
                Label("Will stand", systemImage: "checkmark.seal")
                    .foregroundStyle(FishersTheme.available)
            }

            if let text = p.note, !isMine || !editingNote {
                Text(text).foregroundStyle(.secondary)
            }
        } header: {
            Text("Umpiring")
        } footer: {
            if p.matches == 0 && p.reviews.isEmpty {
                Text(isMine
                     ? "Ask your captain to name you as umpire and it starts counting."
                     : "\(name ?? "They") have not umpired a match here yet.")
            }
        }

        if p.ratingCount > 0 {
            Section("How the ratings fall") {
                ForEach((1...5).reversed(), id: \.self) { n in
                    HStack {
                        Text("\(n)").monospacedDigit().frame(width: 16, alignment: .trailing)
                        ProgressView(
                            value: Double(p.ratingBreakdown[n - 1]),
                            total: Double(max(p.ratingCount, 1))
                        )
                        Text("\(p.ratingBreakdown[n - 1])")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(n) stars, \(p.ratingBreakdown[n - 1]) of \(p.ratingCount)")
                }
            }
        }

        if !p.reviews.isEmpty {
            Section("What the players said") {
                ForEach(p.reviews) { review in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            StarRow(value: review.rating)
                            Text(review.reviewerName)
                                .font(FishersTheme.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let comment = review.comment {
                            Text(comment)
                        }
                        Text(review.matchTitle)
                            .font(FishersTheme.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(FishersTheme.figure()).monospacedDigit()
            Text(label).font(FishersTheme.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            profile = isMine
                ? try await FishersAPI.myUmpiring()
                : try await FishersAPI.umpiring(of: userId!)
            note = profile?.note ?? ""
        } catch {
            self.error = "Could not load the umpiring record"
        }
    }

    private func save(umpires: Bool? = nil, note: String?? = nil) async {
        saving = true
        defer { saving = false }
        do {
            profile = try await FishersAPI.setUmpiring(umpires: umpires, note: note)
            editingNote = false
        } catch {
            self.error = "Could not save that"
        }
    }
}

/// One to five, drawn. Never the only signal — every use pairs it with the
/// number, because five shapes in a row is a hard thing to count at a glance
/// and an impossible one to hear.
struct StarRow: View {
    let value: Int
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { n in
                Image(systemName: n <= value ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(n <= value ? FishersTheme.accent400 : Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) out of 5")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
