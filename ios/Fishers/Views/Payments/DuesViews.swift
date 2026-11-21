import SwiftUI

/// "You owe £15.00" — on Home and in Profile, only while some club is owed
/// something. It opens the list by club; each club opens its pay screen.
struct YouOweSection: View {
    @ObservedObject var store: DuesStore
    /// Profile keeps a way in to past payments once everything is paid;
    /// Home only speaks up when there is something to do.
    var showsWhenPaidUp = false

    var body: some View {
        if let dues = store.dues, dues.owedSummary == nil, showsWhenPaidUp, !dues.clubs.isEmpty {
            Section {
                NavigationLink {
                    DuesListView(store: store)
                } label: {
                    Label(tr("Payments"), systemImage: "banknote")
                        .frame(minHeight: FishersTheme.minTap)
                }
            }
        } else if let dues = store.dues, let summary = dues.owedSummary {
            Section {
                NavigationLink {
                    DuesListView(store: store)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "banknote")
                            .font(.title3)
                            .foregroundStyle(FishersTheme.pitch)
                            .frame(width: 36, height: 36)
                            .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("You owe {amount}.", vars: ["amount": summary]))
                                .font(FishersTheme.headline)
                            Text(subtitle(dues))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: FishersTheme.minTap)
                }
            }
        }
    }

    /// The clubs owed, and a word if some of it is only waiting to be
    /// confirmed.
    private func subtitle(_ dues: MyDues) -> String {
        var parts = [dues.owing.map(\.clubName).joined(separator: ", ")]
        if dues.clubs.contains(where: { $0.waitingCents > 0 }) {
            parts.append(tr("Waiting for the club to confirm"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Everything owed, by club. Waiting amounts read "Waiting for the club to
/// confirm" — they are not owed, but they are not paid either.
struct DuesListView: View {
    @ObservedObject var store: DuesStore

    var body: some View {
        List {
            if let dues = store.dues {
                if dues.clubs.isEmpty {
                    ContentUnavailableView(
                        tr("You're all paid up."),
                        systemImage: "checkmark.seal",
                        description: Text(tr("Nothing to pay. When a club bills you for nets or a match, it shows up here."))
                    )
                }
                ForEach(dues.clubs) { club in
                    Section {
                        NavigationLink {
                            PayScreenView(clubId: club.clubId, clubName: club.clubName)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if club.owedCents > 0 {
                                    Text(tr("You owe {amount}.", vars: ["amount": Money.format(club.owedCents, club.currency)]))
                                        .font(FishersTheme.headline)
                                } else if club.waitingCents == 0 {
                                    Label(tr("You're all paid up."), systemImage: "checkmark.seal.fill")
                                        .foregroundStyle(FishersTheme.available)
                                }
                                if club.waitingCents > 0 {
                                    Text(tr("{amount} waiting for the club to confirm", vars: ["amount": Money.format(club.waitingCents, club.currency)]))
                                        .font(FishersTheme.footnote)
                                        .foregroundStyle(FishersTheme.maybe)
                                }
                                if club.creditCents > 0 {
                                    Text(tr("{amount} in credit", vars: ["amount": Money.format(club.creditCents, club.currency)]))
                                        .font(FishersTheme.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: FishersTheme.minTap)
                        }
                        ForEach(club.shares) { share in
                            ShareLine(share: share)
                        }
                    } header: {
                        Text(club.clubName)
                    }
                }
            } else if let failed = store.failed {
                Text(failed).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle(tr("Payments"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
    }
}
