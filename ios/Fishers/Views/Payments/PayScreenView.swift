import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The copy buttons on the pay screen.
///
/// Anything carrying the account number is put on this phone's pasteboard
/// only — not Universal Clipboard, which would hand it to every Mac and iPad
/// on the same Apple ID — and expires after five minutes, which is longer
/// than it takes to switch to a banking app and paste.
enum Clipboard {
    static func copy(_ text: String, sensitive: Bool = false) {
        if sensitive {
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(5 * 60)]
            )
        } else {
            UIPasteboard.general.string = text
        }
    }
}

/// One thing a banking app asks for, with its own Copy button.
struct CopyRow: View {
    let label: String
    let value: String
    /// What goes on the pasteboard, when it differs from what is shown.
    var copyValue: String? = nil
    var sensitive = false
    var monospaced = false

    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(FishersTheme.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(monospaced ? FishersTheme.body.monospacedDigit().weight(.semibold) : FishersTheme.body.weight(.semibold))
                    .textSelection(.enabled)
                    .privacySensitive(sensitive)
            }
            Spacer(minLength: 8)
            Button {
                Clipboard.copy(copyValue ?? value, sensitive: sensitive)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(copied ? tr("Copied") : tr("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(FishersTheme.subhead.weight(.semibold))
                    .frame(minWidth: 72, minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(tr("Copy {what}", vars: ["what": label.lowercased()]))
        }
        .accessibilityElement(children: .contain)
    }
}

/// A share's state as a small coloured badge. Never colour alone: the word
/// is always there.
struct ShareStateBadge: View {
    let state: ShareState

    var body: some View {
        Text(state.shortLabel)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour.opacity(0.15), in: Capsule())
            .foregroundStyle(colour)
    }

    private var colour: Color {
        switch state {
        case .paid: return FishersTheme.available
        case .waiting, .partPaid: return FishersTheme.maybe
        case .owed: return FishersTheme.unavailable
        default: return .secondary
        }
    }
}

/// Paying one club: how much, where to, the reference, and "I've paid".
///
/// The full account number is shown here and nowhere else, held in memory
/// for as long as the screen is open and never written to disk or a log.
struct PayScreenView: View {
    let clubId: UUID
    var clubName: String? = nil

    @StateObject private var store: PayScreenStore

    init(clubId: UUID, clubName: String? = nil) {
        self.clubId = clubId
        self.clubName = clubName
        _store = StateObject(wrappedValue: PayScreenStore(clubId: clubId))
    }

    var body: some View {
        List {
            if let screen = store.screen {
                amountSection(screen)
                if let notice = store.notice {
                    Section {
                        Label(notice, systemImage: "info.circle")
                            .font(FishersTheme.subhead)
                    }
                }
                detailsSection(screen)
                actionSection(screen)
                claimsSection(screen)
                sharesSection(screen)
            } else if store.isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle(store.screen?.clubName ?? clubName ?? tr("Payments"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: Sections

    private func amountSection(_ screen: PayScreen) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if screen.owedCents > 0 {
                    Text(tr("You owe"))
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                    Text(Money.format(screen.owedCents, screen.currency))
                        .font(FishersTheme.figure(.largeTitle))
                        .foregroundStyle(FishersTheme.pitch)
                } else if screen.waitingCents == 0 {
                    Label(tr("You're all paid up."), systemImage: "checkmark.seal.fill")
                        .font(FishersTheme.headline)
                        .foregroundStyle(FishersTheme.available)
                }
                if screen.waitingCents > 0 {
                    Label(
                        tr("{amount} waiting for the club to confirm", vars: ["amount": Money.format(screen.waitingCents, screen.currency)]),
                        systemImage: "clock"
                    )
                    .font(FishersTheme.subhead)
                    .foregroundStyle(FishersTheme.maybe)
                }
                if screen.owedCents == 0, screen.waitingCents > 0 {
                    Text(tr("You've said you paid. The club just needs to confirm it."))
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
                if screen.creditCents > 0 {
                    Text(tr("{amount} in credit, which pays your next share automatically", vars: ["amount": Money.format(screen.creditCents, screen.currency)]))
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func detailsSection(_ screen: PayScreen) -> some View {
        if let account = screen.payableAccount {
            Section {
                if let changed = account.changedAt {
                    Label(
                        tr("These bank details changed on {date}. If your banking app warns you the name doesn't match, stop and check with the club before paying.",
                           vars: ["date": changed.formatted(.dateTime.day().month(.abbreviated))]),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(FishersTheme.subhead.weight(.semibold))
                    .foregroundStyle(FishersTheme.maybe)
                }
                if screen.owedCents > 0 {
                    CopyRow(
                        label: tr("Amount"),
                        value: Money.format(screen.owedCents, screen.currency),
                        copyValue: Money.plain(screen.owedCents, screen.currency),
                        monospaced: true
                    )
                }
                CopyRow(label: tr("Account name"), value: account.holderName)
                CopyRow(label: tr("Sort code"), value: account.sortCode, monospaced: true)
                CopyRow(label: tr("Account number"), value: account.accountNumber, sensitive: true, monospaced: true)
                CopyRow(label: tr("Reference"), value: screen.reference, monospaced: true)
                if let all = screen.copyAllText {
                    Button {
                        Clipboard.copy(all, sensitive: true)
                        store.notice = tr("Copied {what}", vars: ["what": tr("all the details")])
                    } label: {
                        Label(tr("Copy all"), systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                }
            } header: {
                HStack {
                    Text(tr("Pay by bank transfer"))
                    if account.isPersonal {
                        Spacer()
                        Text(tr("Personal account"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(FishersTheme.maybe)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if account.isPersonal {
                        Text(tr("This is {name}'s own account, which the club uses to collect money.", vars: ["name": account.holderName]))
                    }
                    Text(tr("Use this reference so the club can tell your payment from everyone else's. It's the same every time you pay this club."))
                }
            }
        } else if let why = screen.accountState.explanation, screen.owedCents > 0 || screen.waitingCents > 0 {
            Section {
                Label(why, systemImage: screen.accountState == .frozen ? "hand.raised.fill" : "info.circle")
                    .font(FishersTheme.subhead)
                    .foregroundStyle(screen.accountState == .frozen ? FishersTheme.unavailable : .primary)
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ screen: PayScreen) -> some View {
        if screen.owedCents > 0 {
            Section {
                if screen.payableAccount != nil {
                    Button {
                        Task { await store.claim(method: "transfer") }
                    } label: {
                        Group {
                            if store.isWorking { ProgressView() } else { Text(tr("I've paid")).font(FishersTheme.headline) }
                        }
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FishersTheme.pitch)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Button(tr("I paid cash")) {
                    Task { await store.claim(method: "cash") }
                }
                .font(FishersTheme.subhead)
                .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                .listRowBackground(Color.clear)
            } footer: {
                if screen.payableAccount != nil {
                    Text(tr("Pay in your banking app, then come back and tap I've paid."))
                }
            }
            .disabled(store.isWorking)
        }
    }

    @ViewBuilder
    private func claimsSection(_ screen: PayScreen) -> some View {
        if !screen.claims.isEmpty {
            Section {
                ForEach(screen.claims) { claim in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Money.format(claim.amountCents, claim.currency)) · \(claim.methodLabel)")
                                .font(FishersTheme.subhead.weight(.semibold))
                            Text([claim.reference, claim.createdAt.formatted(date: .abbreviated, time: .shortened)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(tr("Undo")) { Task { await store.undo(claim) } }
                            .buttonStyle(.bordered)
                            .frame(minHeight: FishersTheme.minTap)
                            .disabled(store.isWorking)
                    }
                }
            } header: {
                Text(tr("Waiting for the club to confirm"))
            }
        }
    }

    @ViewBuilder
    private func sharesSection(_ screen: PayScreen) -> some View {
        if !screen.shares.isEmpty {
            Section(tr("What it's for")) {
                ForEach(screen.shares) { share in
                    ShareLine(share: share)
                }
            }
        }
    }
}

/// One share in a list: what, when, how much, where it stands.
struct ShareLine: View {
    let share: ClubShare
    var showsName = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(showsName ? share.name : share.title)
                    .font(FishersTheme.subhead.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
                if let reason = share.reason, share.state == .waived {
                    Text(reason).font(FishersTheme.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.format(share.amountCents, share.currency))
                    .font(FishersTheme.subhead.monospacedDigit())
                ShareStateBadge(state: share.state)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        if showsName { return share.isGuest ? tr("Guest") : nil }
        return share.eventStartAt.formatted(date: .abbreviated, time: .omitted)
    }
}
