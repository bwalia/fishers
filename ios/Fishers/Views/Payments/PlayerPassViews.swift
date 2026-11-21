import SwiftUI

// MARK: - Passes, on the club's pay screen

/// The reader's passes (and those of anybody they pay for), each with where
/// it stands in words; a monthly one with exactly what to type into the
/// banking app; then the passes they could get.
///
/// Failures show here, beside the button that caused them, rather than as an
/// alert: the pay screen has its own alert already.
struct PlayerPassesSection: View {
    @ObservedObject var store: PlayerPassesStore
    let screen: PayScreen
    /// Reloads what is owed: getting a pass charges its first payment.
    let onChange: () async -> Void

    @State private var getting: PassPlan?
    @State private var cancelling: PassHolder?
    @State private var sending: SharedText?

    struct SharedText: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        if store.notice != nil || store.errorMessage != nil {
            Section {
                if let notice = store.notice {
                    Label(notice, systemImage: "info.circle").font(FishersTheme.subhead)
                }
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(FishersTheme.subhead)
                        .foregroundStyle(FishersTheme.unavailable)
                }
            }
        }
        if !store.passes.isEmpty {
            yourPasses
        }
        if !store.offered.isEmpty {
            offers
        }
    }

    // MARK: Yours

    private var yourPasses: some View {
        Section {
            ForEach(store.passes) { holder in
                PassStandingRow(holder: holder, mine: store.isMine(holder), validUntil: store.validUntil(holder))
                if holder.billing == .monthly, let order = holder.standingOrder, !holder.isCancelled {
                    StandingOrderRows(order: order, screen: screen) { text in
                        sending = SharedText(text: text)
                    }
                }
                if !holder.isCancelled {
                    Button(role: .destructive) {
                        store.errorMessage = nil
                        cancelling = holder
                    } label: {
                        Text(store.isMine(holder) ? tr("Cancel my pass") : tr("Cancel their pass"))
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap, alignment: .leading)
                    }
                    .disabled(store.isWorking)
                }
            }
        } header: {
            Text(store.passes.count == 1 ? tr("Your pass") : tr("Your passes"))
        }
        .confirmationDialog(
            cancelling.map { $0.cancelQuestion(forSomeoneElse: !store.isMine($0)) } ?? "",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible,
            presenting: cancelling
        ) { holder in
            Button(tr("Yes, cancel it"), role: .destructive) {
                Task { if await store.cancel(holder) { await onChange() } }
            }
            Button(tr("Never mind"), role: .cancel) {}
        } message: { holder in
            Text(holder.cancelWarning)
        }
        .sheet(item: $sending) { shared in
            // No Copy here: the account number reaches the pasteboard only
            // through the rows' own local, expiring copy.
            ShareSheet(items: [shared.text], excluded: [.copyToPasteboard]) { sending = nil }
        }
    }

    // MARK: Ones to get

    private var offers: some View {
        Section {
            ForEach(store.offered) { plan in
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name)
                        .font(FishersTheme.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.priceWords)
                        .font(FishersTheme.subhead.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.coverWords)
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let only = plan.onlyFor(store.groups) {
                        Text(only)
                            .font(FishersTheme.footnote)
                            .foregroundStyle(FishersTheme.maybe)
                    }
                    Button {
                        store.errorMessage = nil
                        getting = plan
                    } label: {
                        Text(tr("Get this pass"))
                            .font(FishersTheme.headline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.bordered)
                    .tint(FishersTheme.pitch)
                    .disabled(store.isWorking)
                    .padding(.top, 4)
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text(tr("Passes"))
        } footer: {
            Text(tr("A pass covers your sessions, so there's nothing to pay each time."))
        }
        .confirmationDialog(
            getting?.joinQuestion ?? "",
            isPresented: Binding(get: { getting != nil }, set: { if !$0 { getting = nil } }),
            titleVisibility: .visible,
            presenting: getting
        ) { plan in
            let who = store.whoCanGet(plan)
            ForEach(Array(who.enumerated()), id: \.offset) { _, person in
                Button(label(for: person, among: who)) {
                    Task { if await store.join(plan, for: person?.userId) { await onChange() } }
                }
            }
            Button(tr("Never mind"), role: .cancel) {}
        } message: { plan in
            Text(plan.joinExplanation)
        }
    }

    private func label(for person: PersonDues?, among who: [PersonDues?]) -> String {
        guard let person else {
            return who.count == 1 ? tr("Yes, get it") : tr("Get it for me")
        }
        return tr("Get it for {name}", vars: ["name": person.name])
    }
}

/// One pass and where it stands, in words.
struct PassStandingRow: View {
    let holder: PassHolder
    let mine: Bool
    var validUntil: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(holder.planName)
                .font(FishersTheme.headline)
                .fixedSize(horizontal: false, vertical: true)
            if !mine {
                Text(tr("For {name}", vars: ["name": holder.name]))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
            Label(holder.standingWords(validUntil: validUntil), systemImage: symbol)
                .font(FishersTheme.subhead.weight(.semibold))
                .foregroundStyle(colour)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if holder.isInGoodStanding { return "checkmark.seal.fill" }
        return holder.standing == .suspended ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill"
    }

    private var colour: Color {
        if holder.isInGoodStanding { return FishersTheme.available }
        if holder.standing == .suspended { return FishersTheme.unavailable }
        return holder.isCancelled ? .secondary : FishersTheme.maybe
    }
}

/// "Set up your standing order": who, how much, every month, from when and
/// what to write in the reference box, each with Copy, as the banking app
/// asks for them. The bank details are the pay screen's, shown only while
/// the club's pay screen shows them.
struct StandingOrderRows: View {
    let order: StandingOrder
    let screen: PayScreen
    let send: (String) -> Void

    @State private var open = true

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            Text(tr("In your banking app, set up a standing order with these details. It pays the club every month by itself."))
                .font(FishersTheme.subhead)
                .fixedSize(horizontal: false, vertical: true)
            if let account = screen.payableAccount {
                CopyRow(label: tr("Who to pay"), value: account.holderName)
                CopyRow(label: tr("Sort code"), value: account.sortCode, monospaced: true)
                CopyRow(label: tr("Account number"), value: account.accountNumber, sensitive: true, monospaced: true)
            } else {
                Text(tr("The club's bank details show here while a payment is due. Your club secretary can give them to you too."))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
            CopyRow(label: tr("Amount"), value: Money.format(order.amountCents, screen.currency),
                    copyValue: Money.plain(order.amountCents, screen.currency))
            CopyRow(label: tr("How often"), value: order.howOften)
            CopyRow(label: tr("First payment"), value: DayDate.short(order.firstPaymentOn) ?? order.firstPaymentOn)
            CopyRow(label: tr("What to write in the reference box"), value: order.reference, monospaced: true)
            Button {
                send(order.detailsToSend(club: screen.clubName, currency: screen.currency, account: screen.payableAccount))
            } label: {
                Label(tr("Send to someone who pays for me"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap, alignment: .leading)
            }
        } label: {
            Text(tr("Set up your standing order"))
                .font(FishersTheme.headline)
                .frame(minHeight: FishersTheme.minTap)
        }
    }
}

// MARK: - I'm paying for friends too

/// Tick friends from the same sessions; one payment covers the reader and
/// everyone ticked, under the reader's reference.
struct FriendsPaySheet: View {
    let screen: PayScreen

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var payer: PayForOthersStore
    @State private var friends: [Friend] = []
    @State private var loaded = false
    @State private var ticked: Set<UUID> = []
    @State private var finished = false

    struct Friend: Identifiable, Equatable {
        let id: UUID
        let name: String
        let sessions: [String]
    }

    init(screen: PayScreen) {
        self.screen = screen
        _payer = StateObject(wrappedValue: PayForOthersStore(clubId: screen.clubId))
    }

    var body: some View {
        NavigationStack {
            Form {
                if finished, let notice = payer.notice {
                    Section {
                        Label(notice, systemImage: "checkmark.seal.fill")
                            .font(FishersTheme.headline)
                            .foregroundStyle(FishersTheme.available)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Section {
                        bigButton(tr("Done"), prominent: true) { dismiss() }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                } else {
                    pickSection
                    if let problem = payer.problem {
                        Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                    }
                    Section {
                        VStack(spacing: 12) {
                            bigButton(tr("I've paid for us all"), prominent: true) { Task { await pay("transfer") } }
                            bigButton(tr("I paid cash for us all"), prominent: false) { Task { await pay("cash") } }
                        }
                        .disabled(ticked.isEmpty || payer.isWorking)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text(tr("Pay in your banking app first: one payment with your reference, {reference}. Each friend's part is what they owe the club.",
                                vars: ["reference": screen.reference]))
                    }
                }
            }
            .navigationTitle(tr("Paying for friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !finished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("sc.cancel")) { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(payer.isWorking)
            .task { await loadFriends() }
        }
    }

    @ViewBuilder
    private var pickSection: some View {
        Section {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if friends.isEmpty {
                Text(tr("Nobody else from your sessions to pick."))
                    .foregroundStyle(.secondary)
            }
            ForEach(friends) { friend in
                Toggle(isOn: Binding(
                    get: { ticked.contains(friend.id) },
                    set: { on in if on { ticked.insert(friend.id) } else { ticked.remove(friend.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.name)
                        Text(friend.sessions.joined(separator: ", "))
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: FishersTheme.minTap)
            }
        } header: {
            Text(tr("Who are you paying for?"))
        }
    }

    @ViewBuilder
    private func bigButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Group {
                if payer.isWorking { ProgressView() } else { Text(title).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .font(.title3.weight(prominent ? .bold : .semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .tint(FishersTheme.pitch)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// Everybody who said they'd come to the sessions the reader owes for.
    private func loadFriends() async {
        defer { loaded = true }
        let me = session.user?.id
        var found: [UUID: Friend] = [:]
        var order: [UUID] = []
        let sessions = Dictionary(grouping: screen.owedShares.filter { $0.eventId != nil }, by: { $0.eventId! })
        for (eventId, shares) in sessions {
            guard let people = try? await FishersAPI.attendees(eventId: eventId) else { continue }
            let title = shares.first?.title ?? ""
            for person in people where person.status == .going && person.userId != me {
                let before = found[person.userId]
                if before == nil { order.append(person.userId) }
                found[person.userId] = Friend(
                    id: person.userId, name: person.name, sessions: (before?.sessions ?? []) + [title]
                )
            }
        }
        friends = order.compactMap { found[$0] }.sorted { $0.name < $1.name }
    }

    private func pay(_ method: String) async {
        let outcome = await payer.pay(method: method, people: Array(ticked), includeMe: screen.owedCents > 0)
        if !outcome.isFailure { finished = true }
    }
}

// MARK: - Pay for everyone

/// A parent's one payment for themselves and everyone they pay for at one
/// club: one total, one set of bank details, one reference.
struct PayForEveryoneView: View {
    let group: DuesGroup
    var onPaid: () async -> Void = {}

    @StateObject private var screen: PayScreenStore
    @StateObject private var payer: PayForOthersStore
    @State private var finished = false

    init(group: DuesGroup, onPaid: @escaping () async -> Void = {}) {
        self.group = group
        self.onPaid = onPaid
        _screen = StateObject(wrappedValue: PayScreenStore(clubId: group.clubId))
        _payer = StateObject(wrappedValue: PayForOthersStore(clubId: group.clubId))
    }

    var body: some View {
        List {
            Section {
                Text(tr("You owe {amount} for {who}.", vars: [
                    "amount": Money.format(group.totalOwedCents, group.currency), "who": group.whoWords,
                ]))
                .font(.title.weight(.bold))
                .foregroundStyle(FishersTheme.pitch)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                if let mine = group.mine, mine.owedCents > 0 {
                    LabeledContent(tr("You"), value: Money.format(mine.owedCents, mine.currency))
                }
                ForEach(group.peopleOwing) { person in
                    LabeledContent(person.name, value: Money.format(person.dues.owedCents, person.dues.currency))
                }
            }

            if finished, let notice = payer.notice {
                Section {
                    Label(notice, systemImage: "checkmark.seal.fill")
                        .font(FishersTheme.headline)
                        .foregroundStyle(FishersTheme.available)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                detailsSection
                actionSection
                if let problem = payer.problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle(tr("Pay for everyone"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await screen.load() }
    }

    @ViewBuilder
    private var detailsSection: some View {
        if let paying = screen.screen, let account = paying.payableAccount {
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
                CopyRow(label: tr("Name"), value: account.holderName)
                CopyRow(label: tr("Sort code"), value: account.sortCode, monospaced: true)
                CopyRow(label: tr("Account number"), value: account.accountNumber, sensitive: true, monospaced: true)
                CopyRow(label: tr("Amount"), value: Money.format(group.totalOwedCents, group.currency),
                        copyValue: Money.plain(group.totalOwedCents, group.currency))
                CopyRow(label: tr("What to write in the reference box"), value: paying.reference, monospaced: true)
            } footer: {
                Text(tr("One payment for everyone, with this reference. The club sees who it's for."))
            }
        } else if screen.screen != nil || screen.errorMessage != nil {
            Section {
                Label(tr("The club's bank details aren't showing here. Ask your club secretary for them, then pay and come back."),
                      systemImage: "info.circle")
                    .font(FishersTheme.subhead)
            }
        } else {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private var actionSection: some View {
        Section {
            VStack(spacing: 12) {
                Button {
                    Task { await pay("transfer") }
                } label: {
                    Group {
                        if payer.isWorking { ProgressView() } else { Text(tr("I've paid for everyone")).lineLimit(1).minimumScaleFactor(0.8) }
                    }
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.pitch)
                Button {
                    Task { await pay("cash") }
                } label: {
                    Text(tr("I paid cash for everyone"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .tint(FishersTheme.pitch)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .disabled(payer.isWorking)
        } footer: {
            Text(tr("Pay in your banking app, then come back and tap I've paid."))
        }
    }

    private func pay(_ method: String) async {
        let outcome = await payer.pay(
            method: method, people: group.peopleOwing.map(\.userId), includeMe: group.includeMe
        )
        guard !outcome.isFailure else { return }
        finished = true
        await onPaid()
    }
}
