import SwiftUI
import UIKit

/// After the bill goes out: tell the group. The messages are the server's —
/// "🏏 Friday nets, Fri 20 Nov: £15.00 each. Tap to pay: …" — and the link
/// opens a page where players pay without signing in.
///
/// Straight into WhatsApp when it is on the phone, the share sheet otherwise;
/// "Other apps" always reaches the share sheet. The link is only made when
/// somebody taps, never just by opening the event.
///
/// A session's bill and a group fee share the same way; each says how to
/// get its link and how to switch it off.
struct BillShareBlock: View {
    /// The link and its messages, or nil after a failure the caller shows.
    let makeLink: () async -> BillLink?
    let switchOff: () async -> Void
    /// Somebody still owes: worth a reminder.
    let anyoneOwes: Bool
    /// Whether a link is open now, where the caller has asked (a group fee
    /// reads it with `GET /bills/{id}/link`). Nil when not known: switching
    /// it off is offered anyway.
    let linkIsOpen: Bool?

    init(
        anyoneOwes: Bool, linkIsOpen: Bool? = nil,
        makeLink: @escaping () async -> BillLink?, switchOff: @escaping () async -> Void
    ) {
        self.anyoneOwes = anyoneOwes
        self.linkIsOpen = linkIsOpen
        self.makeLink = makeLink
        self.switchOff = switchOff
    }

    init(store: EventMoneyStore, anyoneOwes: Bool) {
        self.init(anyoneOwes: anyoneOwes, makeLink: { await store.billLink() }, switchOff: { await store.switchLinkOff() })
    }

    @State private var sharing: SharedText?
    @State private var confirmOff = false
    @State private var copied = false

    struct SharedText: Identifiable {
        let id = UUID()
        let text: String
    }

    enum Message { case bill, reminder }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Tell the group"))
                .font(FishersTheme.subhead.weight(.semibold))
            Button {
                Task { await share(.bill, viaWhatsApp: true) }
            } label: {
                Label(tr("Share the bill"), systemImage: "paperplane.fill")
                    .font(FishersTheme.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.pitch)
            if anyoneOwes {
                Button {
                    Task { await share(.reminder, viaWhatsApp: true) }
                } label: {
                    Label(tr("Remind who hasn't paid"), systemImage: "bell")
                        .font(FishersTheme.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.bordered)
                .tint(FishersTheme.pitch)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { smallButtons }
                VStack(alignment: .leading, spacing: 8) { smallButtons }
            }
        }
        .confirmationDialog(tr("Switch the pay link off?"), isPresented: $confirmOff, titleVisibility: .visible) {
            Button(tr("Switch it off"), role: .destructive) { Task { await switchOff() } }
            Button(tr("Never mind"), role: .cancel) {}
        } message: {
            Text(tr("Anyone who opens it is asked for the latest one. Sharing the bill again makes a new link."))
        }
        .sheet(item: $sharing) { shared in
            ShareSheet(items: [shared.text]) { sharing = nil }
        }
    }

    @ViewBuilder
    private var smallButtons: some View {
        Button {
            Task { await copyLink() }
        } label: {
            Label(copied ? tr("Copied") : tr("Copy link"), systemImage: copied ? "checkmark" : "link")
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: FishersTheme.minTap)
        }
        .buttonStyle(.bordered)
        if WhatsApp.isInstalled {
            Menu {
                Button(tr("Share the bill")) { Task { await share(.bill, viaWhatsApp: false) } }
                if anyoneOwes {
                    Button(tr("Remind who hasn't paid")) { Task { await share(.reminder, viaWhatsApp: false) } }
                }
            } label: {
                Label(tr("Other apps"), systemImage: "square.and.arrow.up")
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.bordered)
        }
        if linkIsOpen != false {
            Menu {
                Button(tr("Switch the pay link off"), role: .destructive) { confirmOff = true }
            } label: {
                Label(tr("More"), systemImage: "ellipsis.circle")
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(tr("More about the pay link"))
        }
    }

    private func share(_ message: Message, viaWhatsApp: Bool) async {
        guard let link = await makeLink() else { return }
        let text = message == .bill ? link.billMessage : link.reminderMessage
        if viaWhatsApp, WhatsApp.isInstalled, let url = WhatsApp.sendURL(text),
           await UIApplication.shared.open(url) {
            return
        }
        sharing = SharedText(text: text)
    }

    private func copyLink() async {
        guard let link = await makeLink(), !link.url.isEmpty else { return }
        Clipboard.copy(link.url)
        copied = true
        try? await Task.sleep(for: .seconds(2))
        copied = false
    }
}

// MARK: - Who paid cash?

/// Cash at the ground: tick who handed money over, then save. A money admin's
/// tick counts as paid; a captain's waits for the treasurer to have the cash.
struct CashChecklistSheet: View {
    @ObservedObject var store: EventMoneyStore
    /// Still owing something on this bill.
    let shares: [ClubShare]
    /// Whether the person ticking looks after the club's money.
    let countsAsPaid: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var ticked: Set<UUID> = []
    @State private var problem: String?

    private var tickedShares: [ClubShare] { shares.filter { ticked.contains($0.id) } }
    private var currency: String { shares.first?.currency ?? Money.fallbackCurrency }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(shares) { share in
                        Toggle(isOn: Binding(
                            get: { ticked.contains(share.id) },
                            set: { on in if on { ticked.insert(share.id) } else { ticked.remove(share.id) } }
                        )) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(share.name)
                                    if share.isGuest {
                                        Text(tr("Guest")).font(FishersTheme.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Money.format(share.leftCents, share.currency))
                                    .font(FishersTheme.subhead.monospacedDigit())
                            }
                        }
                        .frame(minHeight: FishersTheme.minTap)
                    }
                } footer: {
                    Text(countsAsPaid
                         ? tr("Tick everyone who gave you cash. They're marked as paid.")
                         : tr("Tick everyone who gave you cash. The treasurer ticks it off once they have it."))
                }

                if !ticked.isEmpty {
                    Section {
                        Text(tickedShares.count == 1
                             ? tr("{n} person · {total} in all", vars: ["n": 1, "total": Money.format(total, currency)])
                             : tr("{n} people · {total} in all", vars: ["n": tickedShares.count, "total": Money.format(total, currency)]))
                            .font(FishersTheme.headline)
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(tr("Who paid cash?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isWorking {
                        ProgressView()
                    } else {
                        Button(tr("Save")) { Task { await save() } }
                            .disabled(ticked.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
        }
    }

    private var total: Int { tickedShares.reduce(0) { $0 + $1.leftCents } }

    private func save() async {
        problem = nil
        if let failure = await store.recordCash(Array(ticked)).failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}
