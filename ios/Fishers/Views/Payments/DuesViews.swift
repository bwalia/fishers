import SwiftUI

/// "You owe £15.00" — on Home and in Profile, only while some club is owed
/// something. It opens the list by club; each club opens its pay screen.
struct YouOweSection: View {
    @ObservedObject var store: DuesStore
    /// Profile keeps a way in to past payments once everything is paid;
    /// Home only speaks up when there is something to do.
    var showsWhenPaidUp = false

    var body: some View {
        if let dues = store.dues, dues.owedSummary == nil, showsWhenPaidUp, !(dues.clubs.isEmpty && dues.people.isEmpty) {
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
        var parts = [dues.groups.filter { $0.totalOwedCents > 0 }.map(\.clubName).joined(separator: ", ")]
        if dues.clubs.contains(where: { $0.waitingCents > 0 }) || dues.people.contains(where: { $0.dues.waitingCents > 0 }) {
            parts.append(tr("Waiting for the club to confirm"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Everything owed, by club. Waiting amounts read "Waiting for the club to
/// confirm" — they are not owed, but they are not paid either.
///
/// Somebody who pays for others (a parent for their juniors) sees each of
/// them as their own block under the club, then one Pay for everyone.
struct DuesListView: View {
    @ObservedObject var store: DuesStore

    var body: some View {
        List {
            if let dues = store.dues {
                if dues.clubs.isEmpty && dues.people.isEmpty {
                    ContentUnavailableView(
                        tr("You're all paid up."),
                        systemImage: "checkmark.seal",
                        description: Text(tr("Nothing to pay. When a club bills you for nets or a match, it shows up here."))
                    )
                }
                ForEach(dues.groups) { group in
                    if let club = group.mine {
                        Section {
                            NavigationLink {
                                PayScreenView(clubId: club.clubId, clubName: club.clubName)
                            } label: {
                                DuesTotals(dues: club, paidUp: tr("You're all paid up.")) {
                                    tr("You owe {amount}.", vars: ["amount": $0])
                                }
                            }
                            ForEach(club.shares) { share in
                                ShareLine(share: share)
                            }
                        } header: {
                            Text(club.clubName)
                        }
                    }
                    ForEach(group.people) { person in
                        Section {
                            DuesTotals(dues: person.dues, paidUp: tr("All paid up.")) {
                                tr("{name} owes {amount}.", vars: ["name": firstName(person.name), "amount": $0])
                            }
                            ForEach(person.dues.shares) { share in
                                ShareLine(share: share, forSomeoneElse: true)
                            }
                        } header: {
                            Text([person.name, group.clubName].joined(separator: " · "))
                        } footer: {
                            Text(tr("You pay for {name}.", vars: ["name": firstName(person.name)]))
                        }
                    }
                    if group.canPayForEveryone {
                        Section {
                            NavigationLink {
                                PayForEveryoneView(group: group) { await store.load() }
                            } label: {
                                Label(tr("Pay for everyone"), systemImage: "person.3.fill")
                                    .font(FishersTheme.headline)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(FishersTheme.pitch)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        } footer: {
                            Text(tr("One payment of {amount} for {who}, with one reference.", vars: [
                                "amount": Money.format(group.totalOwedCents, group.currency), "who": group.whoWords,
                            ]))
                        }
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

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// What one person owes one club, waits on, and holds in credit.
private struct DuesTotals: View {
    let dues: ClubDues
    let paidUp: String
    let owedWords: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dues.owedCents > 0 {
                Text(owedWords(Money.format(dues.owedCents, dues.currency)))
                    .font(FishersTheme.headline)
            } else if dues.waitingCents == 0 {
                Label(paidUp, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(FishersTheme.available)
            }
            if dues.waitingCents > 0 {
                Text(tr("{amount} waiting for the club to confirm", vars: ["amount": Money.format(dues.waitingCents, dues.currency)]))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(FishersTheme.maybe)
            }
            if dues.creditCents > 0 {
                Text(tr("{amount} in credit", vars: ["amount": Money.format(dues.creditCents, dues.currency)]))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: FishersTheme.minTap)
    }
}
