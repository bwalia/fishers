import PhotosUI
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

/// One thing a banking app asks for, big, with its own Copy button.
struct CopyRow: View {
    let label: String
    let value: String
    /// What goes on the pasteboard, when it differs from what is shown.
    var copyValue: String? = nil
    var sensitive = false
    var monospaced = false

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(FishersTheme.subhead)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // The value and its button side by side while they fit; the
            // button goes underneath at the largest text sizes rather than
            // squeezing a sort code into a column one digit wide.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    valueText
                    Spacer(minLength: 8)
                    copyButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    valueText
                    copyButton
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var valueText: some View {
        Text(value)
            .font(monospaced ? Font.title3.monospacedDigit().weight(.semibold) : Font.title3.weight(.semibold))
            .textSelection(.enabled)
            .privacySensitive(sensitive)
    }

    private var copyButton: some View {
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
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 72, minHeight: FishersTheme.minTap)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(tr("Copy {what}", vars: ["what": label.lowercased()]))
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
        case .paid, .covered: return FishersTheme.available
        case .waiting, .partPaid: return FishersTheme.maybe
        case .owed: return FishersTheme.unavailable
        default: return .secondary
        }
    }
}

/// Paying one club, for somebody who doesn't use banking apps much: what is
/// owed and for what, who the money goes to, four things to copy, how to do
/// it the first time, then "I've paid" — with Undo and a screenshot after.
///
/// The full account number is shown here and nowhere else, held in memory
/// for as long as the screen is open and never written to disk or a log.
struct PayScreenView: View {
    let clubId: UUID
    var clubName: String? = nil

    @StateObject private var store: PayScreenStore
    @State private var guideOpen: Bool
    @State private var sendingDetails = false

    init(clubId: UUID, clubName: String? = nil) {
        self.clubId = clubId
        self.clubName = clubName
        let store = PayScreenStore(clubId: clubId)
        _store = StateObject(wrappedValue: store)
        // Open the first time; folded away once they've paid this club before.
        _guideOpen = State(initialValue: !store.hasPaidBefore)
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
                if let account = screen.payableAccount {
                    payeeSection(screen, account)
                    if screen.owedCents > 0 {
                        guideSection(screen, account)
                    }
                } else if let why = screen.accountState.explanation, screen.owedCents > 0 || screen.waitingCents > 0 {
                    Section {
                        Label(why, systemImage: screen.accountState == .frozen ? "hand.raised.fill" : "info.circle")
                            .font(FishersTheme.subhead)
                            .foregroundStyle(screen.accountState == .frozen ? FishersTheme.unavailable : .primary)
                    }
                }
                actionSection(screen)
                claimsSection(screen)
                sendSection(screen)
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
        .sheet(isPresented: $sendingDetails) {
            if let text = store.screen?.detailsToSend {
                // No Copy in this sheet: the account number reaches the
                // pasteboard only through the rows above.
                ShareSheet(items: [text], excluded: [.copyToPasteboard]) { sendingDetails = false }
            }
        }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: 1. What is owed

    private func amountSection(_ screen: PayScreen) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if screen.owedCents > 0 {
                    Text(screen.owedHeadline)
                        .font(.title.weight(.bold))
                        .foregroundStyle(FishersTheme.pitch)
                        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: 2–3. Who to pay, and the four things to copy

    private func payeeSection(_ screen: PayScreen, _ account: BankDetails) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.payeeSentence)
                    .font(FishersTheme.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let own = account.ownAccountSentence {
                    Text(own)
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            if let changed = account.changedAt {
                Label(
                    tr("These bank details changed on {date}. If your banking app warns you the name doesn't match, stop and check with the club before paying.",
                       vars: ["date": changed.formatted(.dateTime.day().month(.abbreviated))]),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(FishersTheme.subhead.weight(.semibold))
                .foregroundStyle(FishersTheme.maybe)
            }
            CopyRow(label: tr("Name"), value: account.holderName)
            CopyRow(label: tr("Sort code"), value: account.sortCode, monospaced: true)
            CopyRow(label: tr("Account number"), value: account.accountNumber, sensitive: true, monospaced: true)
            CopyRow(label: tr("What to write in the reference box"), value: screen.reference, monospaced: true)
        } footer: {
            Text(tr("Use this reference so the club can tell your payment from everyone else's. It's the same every time you pay this club."))
        }
    }

    // MARK: 4. How to do it

    private func guideSection(_ screen: PayScreen, _ account: BankDetails) -> some View {
        Section {
            DisclosureGroup(isExpanded: $guideOpen) {
                PayGuideStep(number: 1, symbol: "building.columns", text: tr("Open your banking app."))
                PayGuideStep(number: 2, symbol: "person.badge.plus",
                          text: tr("Add a new payee. Copy each line above and paste it in."))
                PayGuideStep(number: 3, symbol: "checkmark.circle",
                          text: tr("Send {amount}, then come back here and tap I've paid.",
                                   vars: ["amount": Money.format(screen.owedCents, screen.currency)]))
            } label: {
                Text(store.hasPaidBefore
                     ? tr("Pay {name} as usual.", vars: ["name": account.payeeShortName])
                     : tr("First time? Here's how"))
                    .font(FishersTheme.headline)
                    .frame(minHeight: FishersTheme.minTap)
            }
        }
    }

    // MARK: 5. I've paid, I paid cash

    @ViewBuilder
    private func actionSection(_ screen: PayScreen) -> some View {
        if screen.owedCents > 0 {
            Section {
                VStack(spacing: 12) {
                    if screen.payableAccount != nil {
                        Button {
                            Task { await store.claim(method: "transfer") }
                        } label: {
                            Group {
                                if store.isWorking { ProgressView() } else { Text(tr("I've paid")).lineLimit(1) }
                            }
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FishersTheme.pitch)
                    }
                    Button {
                        Task { await store.claim(method: "cash") }
                    } label: {
                        Text(tr("I paid cash"))
                            .lineLimit(1)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .tint(FishersTheme.pitch)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if screen.payableAccount != nil {
                    Text(tr("Pay in your banking app, then come back and tap I've paid."))
                }
            }
            .disabled(store.isWorking)
        }
    }

    // MARK: 6. Waiting: Undo, and a screenshot

    @ViewBuilder
    private func claimsSection(_ screen: PayScreen) -> some View {
        if !screen.claims.isEmpty {
            Section {
                ForEach(screen.claims) { claim in
                    WaitingPaymentRow(store: store, payment: claim)
                }
            } header: {
                Text(tr("Waiting for the club to confirm"))
            } footer: {
                if screen.claims.contains(where: { $0.method == "transfer" && !$0.hasScreenshot }) {
                    Text(tr("A screenshot of the payment from your banking app helps the club find it. You don't have to add one."))
                }
            }
        }
    }

    // MARK: 7. For someone else to pay

    @ViewBuilder
    private func sendSection(_ screen: PayScreen) -> some View {
        if screen.owedCents > 0, screen.detailsToSend != nil {
            Section {
                Button {
                    sendingDetails = true
                } label: {
                    Label(tr("Send these details to someone"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap, alignment: .leading)
                }
            } footer: {
                Text(tr("For a son or daughter, say, who does your banking."))
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

/// One step of "First time? Here's how": a picture and a sentence.
private struct PayGuideStep: View {
    let number: Int
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(FishersTheme.pitch)
                .frame(width: 44, height: 44)
                .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(number)")
                    .font(FishersTheme.overline)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(FishersTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A payment the club hasn't checked yet: Undo, and — for a transfer — an
/// optional screenshot from the photo library.
private struct WaitingPaymentRow: View {
    @ObservedObject var store: PayScreenStore
    let payment: ClubPayment

    @State private var picked: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(Money.format(payment.amountCents, payment.currency)) · \(payment.methodLabel)")
                    .font(FishersTheme.subhead.weight(.semibold))
                Text(payment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
                if payment.hasScreenshot {
                    Label(tr("Screenshot added"), systemImage: "photo.badge.checkmark")
                        .font(FishersTheme.footnote)
                        .foregroundStyle(FishersTheme.available)
                }
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                defer { picked = nil }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await store.addScreenshot(data, to: payment)
                } else {
                    store.errorMessage = tr("That picture couldn't be read. Try a screenshot instead.")
                }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            Task { await store.undo(payment) }
        } label: {
            Text(tr("Undo"))
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: FishersTheme.minTap)
        }
        .buttonStyle(.bordered)
        .disabled(store.isWorking)
        if payment.method == "transfer", !payment.hasScreenshot {
            let uploading = store.addingScreenshotTo == payment.id
            PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                Group {
                    if uploading {
                        ProgressView()
                    } else {
                        Label(tr("Add a screenshot"), systemImage: "photo.badge.plus")
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.bordered)
            .disabled(store.addingScreenshotTo != nil)
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
