import SwiftUI

/// Captain-only availability-aware roster builder.
struct SquadPickerView: View {
    let attendees: [AttendeeSummary]
    @State private var selected: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss

    private var pool: [AttendeeSummary] {
        attendees.sorted { lhs, rhs in
            rank(lhs) < rank(rhs)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Suggested (available + going)") {
                    ForEach(pool) { player in
                        Button {
                            if selected.contains(player.userId) {
                                selected.remove(player.userId)
                            } else if selected.count < 11 {
                                selected.insert(player.userId)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(player.name)
                                    Text(subtitle(player))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected.contains(player.userId) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(FishersTheme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Starting XI (\(selected.count)/11)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { dismiss() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func rank(_ a: AttendeeSummary) -> Int {
        let avail: Int = switch a.availability {
        case .available: 0
        case .maybe: 1
        case .unavailable: 3
        case nil: 2
        }
        let rsvp: Int = switch a.status {
        case .going: 0
        case .maybe: 1
        case .invited: 2
        case .notGoing: 4
        }
        return avail + rsvp
    }

    private func subtitle(_ a: AttendeeSummary) -> String {
        let avail = a.availability?.label ?? "No calendar"
        return "\(a.status.rawValue) · \(avail)"
    }
}
