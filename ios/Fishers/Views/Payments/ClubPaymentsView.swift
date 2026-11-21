import SwiftUI

/// Club → Manage → Payments, for the club's owner, secretaries and
/// treasurers: the bank details, payments to check, who owes what, recent
/// bills and the settings.
///
/// Whether somebody gets this screen is the server's call — a 403 on
/// `/clubs/{id}/money` — not a role worked out on the phone.
struct ClubPaymentsView: View {
    @ObservedObject var store: ClubMoneyStore

    @State private var editingDetails = false
    @State private var freezing: PayoutAccount?
    @State private var freezeReason = ""
    @State private var removing: PayoutAccount?
    @State private var rejecting: ClubPayment?
    @State private var rejectReason = ""
    @State private var recording: PayerAction?

    /// Record cash for somebody, or refund their credit.
    struct PayerAction: Identifiable {
        enum Kind { case record, refund }
        let kind: Kind
        let member: MemberBalance
        var id: String { "\(kind)-\(member.id)" }
    }

    var body: some View {
        List {
            if let overview = store.overview {
                if let notice = store.notice {
                    Section {
                        Label(notice, systemImage: "info.circle").font(FishersTheme.subhead)
                    }
                }
                bankDetailsSection(overview.account)
                toCheckSection(overview)
                whoOwesSection(overview)
                billsSection(overview)
                settingsSection(overview.settings)
            } else if store.forbidden {
                Section {
                    Label(tr("Only the club owner, a secretary or a treasurer can look after the club's money."), systemImage: "lock")
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                }
            } else if store.isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .disabled(store.isWorking)
        .task { if store.overview == nil { await store.load() } }
        .refreshable { await store.load() }
        .sheet(isPresented: $editingDetails) {
            // Any details already there, even frozen ones, make this a change
            // that waits its 24 hours.
            BankDetailsForm(store: store, isChange: !(store.overview?.account.isEmpty ?? true))
        }
        .sheet(item: $recording) { action in
            RecordPaymentSheet(store: store, action: action, currency: store.overview?.currency ?? Money.fallbackCurrency)
        }
        .alert(tr("Why are you freezing them? (optional)"), isPresented: Binding(get: { freezing != nil }, set: { if !$0 { freezing = nil } })) {
            TextField(tr("Say why, in a few words."), text: $freezeReason)
            Button(tr("Freeze"), role: .destructive) {
                guard let account = freezing else { return }
                let reason = freezeReason
                freezeReason = ""
                Task { await store.freeze(account, reason: reason) }
            }
            Button(tr("Never mind"), role: .cancel) { freezeReason = "" }
        } message: {
            Text(tr("Everyone who looks after the club's money is told. Players are told not to pay until the club owner has looked."))
        }
        .confirmationDialog(
            removing?.state == .pending
                ? tr("Cancel this change? The details players pay into stay as they are.")
                : tr("Remove these bank details? Players can't pay by transfer until new ones are added."),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { account in
            Button(account.state == .pending ? tr("Yes, cancel the change") : tr("Yes, remove them"), role: .destructive) {
                Task { await store.retire(account) }
            }
            Button(tr("Never mind"), role: .cancel) {}
        }
        .alert(
            tr("What's wrong with it?"),
            isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })
        ) {
            TextField(tr("Say why, in a few words."), text: $rejectReason)
            Button(tr("Not received"), role: .destructive) {
                guard let payment = rejecting else { return }
                let reason = rejectReason
                rejectReason = ""
                Task { await store.reject(payment, reason: reason) }
            }
            .disabled(rejectReason.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(tr("Never mind"), role: .cancel) { rejectReason = "" }
        } message: {
            Text(tr("{name} is told, and reminders start again. “Nothing with that reference by Monday” helps them find it.",
                    vars: ["name": rejecting?.name ?? ""]))
        }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: Bank details

    @ViewBuilder
    private func bankDetailsSection(_ accounts: PayoutAccounts) -> some View {
        Section {
            if let current = accounts.current {
                accountRow(current, heading: tr("Players pay into"))
                if !current.readable {
                    Label(tr("These details can't be read any more. Enter them again."), systemImage: "exclamationmark.triangle.fill")
                        .font(FishersTheme.footnote)
                        .foregroundStyle(FishersTheme.unavailable)
                }
                if accounts.canManage {
                    HStack {
                        Button(tr("Freeze")) { freezing = current }
                        Spacer()
                        Button(tr("Remove"), role: .destructive) { removing = current }
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: FishersTheme.minTap)
                }
            }

            if let pending = accounts.pending {
                accountRow(pending, heading: tr("A change waiting to go live"))
                Text(tr("Goes live {when}. Not right? Freeze it before then.", vars: [
                    "when": pending.liveFrom.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()),
                ]))
                .font(FishersTheme.footnote)
                .foregroundStyle(FishersTheme.maybe)
                if accounts.canManage {
                    HStack {
                        Button(tr("Freeze")) { freezing = pending }
                        Spacer()
                        Button(tr("Cancel the change"), role: .destructive) { removing = pending }
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: FishersTheme.minTap)
                }
            }

            if let frozen = accounts.frozen {
                accountRow(frozen, heading: tr("Frozen"))
                Text(frozen.freezeReason.map { tr("Frozen: {reason}. Players are told not to pay until the club owner has looked.", vars: ["reason": $0]) }
                     ?? tr("Frozen. Players are told not to pay until the club owner has looked."))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(FishersTheme.unavailable)
                if accounts.isOwner {
                    HStack {
                        Button(tr("Unfreeze")) { Task { await store.unfreeze(frozen) } }
                        Spacer()
                        Button(tr("Remove"), role: .destructive) { removing = frozen }
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: FishersTheme.minTap)
                } else {
                    Text(tr("Only the club owner can unfreeze or remove frozen details."))
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if accounts.isEmpty {
                Text(tr("Add the account players should pay into. The club's first details go live straight away."))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }

            if accounts.canManage {
                Button {
                    editingDetails = true
                } label: {
                    Label(accounts.current == nil && accounts.pending == nil ? tr("Add bank details") : tr("Change bank details"),
                          systemImage: accounts.current == nil ? "plus" : "pencil")
                        .frame(minHeight: FishersTheme.minTap)
                }
            }
        } header: {
            Text(tr("Bank details"))
        }
    }

    private func accountRow(_ account: PayoutAccount, heading: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(heading)
                .font(FishersTheme.overline)
                .foregroundStyle(FishersTheme.pitch)
            Text(account.holderName).font(FishersTheme.headline)
            Text(account.masked)
                .font(FishersTheme.subhead.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(account.label)
                if account.isPersonal {
                    Text(verbatim: "·")
                    Text(tr("Personal account")).foregroundStyle(FishersTheme.maybe)
                }
            }
            .font(FishersTheme.footnote)
            .foregroundStyle(.secondary)
            if let added = account.createdAt {
                Text(account.createdByName.map {
                    tr("Added by {name} on {date}", vars: ["name": $0, "date": added.formatted(date: .abbreviated, time: .omitted)])
                } ?? tr("Added on {date}", vars: ["date": added.formatted(date: .abbreviated, time: .omitted)]))
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Payments to check

    @ViewBuilder
    private func toCheckSection(_ overview: MoneyOverview) -> some View {
        Section {
            if overview.toCheck.isEmpty {
                Text(tr("Nothing to check. When a player says they've paid, it shows up here."))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(overview.toCheck) { payment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(payment.name).font(FishersTheme.subhead.weight(.semibold))
                        Spacer()
                        Text(Money.format(payment.amountCents, payment.currency))
                            .font(FishersTheme.subhead.monospacedDigit().weight(.semibold))
                    }
                    Text([payment.methodLabel, payment.reference, payment.createdAt.formatted(date: .abbreviated, time: .shortened)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                    if let note = payment.note {
                        Text(note).font(FishersTheme.footnote)
                    }
                    HStack {
                        Button {
                            Task { await store.confirm(payment) }
                        } label: {
                            Label(tr("Received"), systemImage: "checkmark")
                                .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FishersTheme.available)
                        Button {
                            rejecting = payment
                        } label: {
                            Label(tr("Not received"), systemImage: "xmark")
                                .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                        }
                        .buttonStyle(.bordered)
                        .tint(FishersTheme.unavailable)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text(tr("Payments to check"))
                if !overview.toCheck.isEmpty {
                    Text("\(overview.toCheck.count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(FishersTheme.maybe, in: Capsule())
                        .foregroundStyle(.white)
                        .accessibilityLabel(tr("{n} to check", vars: ["n": overview.toCheck.count]))
                }
            }
        } footer: {
            if !overview.toCheck.isEmpty {
                Text(tr("Check each one arrived in your banking app, then tick it off."))
            }
        }
    }

    // MARK: Who owes what

    @ViewBuilder
    private func whoOwesSection(_ overview: MoneyOverview) -> some View {
        Section {
            if let totals = overview.totals {
                LabeledContent(tr("Still owed"), value: Money.format(totals.owedCents, overview.currency))
                if totals.waitingCents > 0 {
                    LabeledContent(tr("To check"), value: Money.format(totals.waitingCents, overview.currency))
                }
                if totals.creditCents > 0 {
                    LabeledContent(tr("Credit held"), value: Money.format(totals.creditCents, overview.currency))
                }
            }
            if overview.members.isEmpty {
                Label(tr("Nobody owes the club anything."), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(FishersTheme.available)
            }
            ForEach(overview.members) { member in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(FishersTheme.subhead.weight(.medium))
                            if member.userId == nil {
                                Text(tr("Guest")).font(FishersTheme.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if member.owedCents > 0 {
                                Text(Money.format(member.owedCents, overview.currency))
                                    .font(FishersTheme.subhead.monospacedDigit())
                                    .foregroundStyle(FishersTheme.unavailable)
                            }
                            if member.waitingCents > 0 {
                                Text(tr("{amount} to check", vars: ["amount": Money.format(member.waitingCents, overview.currency)]))
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(FishersTheme.maybe)
                            }
                            if member.creditCents > 0 {
                                Text(tr("{amount} in credit", vars: ["amount": Money.format(member.creditCents, overview.currency)]))
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Button(tr("Record cash")) { recording = PayerAction(kind: .record, member: member) }
                        if member.creditCents > 0 {
                            Spacer()
                            Button(tr("Refund")) { recording = PayerAction(kind: .refund, member: member) }
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(FishersTheme.subhead)
                    .frame(minHeight: FishersTheme.minTap)
                }
            }
        } header: {
            Text(tr("Who owes what"))
        }
    }

    // MARK: Recent bills

    @ViewBuilder
    private func billsSection(_ overview: MoneyOverview) -> some View {
        if !overview.bills.isEmpty {
            Section(tr("Recent bills")) {
                ForEach(overview.bills) { bill in
                    NavigationLink {
                        EventDetailView(eventId: bill.eventId)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(bill.title).font(FishersTheme.subhead.weight(.medium))
                                Spacer()
                                Text(Money.format(bill.totalCents, bill.currency))
                                    .font(FishersTheme.subhead.monospacedDigit())
                            }
                            Text(billLine(bill))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: FishersTheme.minTap)
                    }
                }
            }
        }
    }

    /// "Fri 20 Nov · 4 people · 2 unpaid · 1 to check".
    private func billLine(_ bill: BillSummary) -> String {
        var parts = [
            bill.eventStartAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
            bill.people == 1 ? tr("{n} person", vars: ["n": 1]) : tr("{n} people", vars: ["n": bill.people]),
        ]
        if bill.unpaid > 0 { parts.append(tr("{n} unpaid", vars: ["n": bill.unpaid])) }
        if bill.waiting > 0 { parts.append(tr("{n} to check", vars: ["n": bill.waiting])) }
        if bill.unpaid == 0, bill.waiting == 0 { parts.append(tr("Paid")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Settings

    /// The usual choices between the server's 1 hour and 14 days, plus
    /// whatever the club has now — a stepper over 336 values is a lot of taps.
    static func afterHours(including current: Int) -> [Int] {
        Array(Set([1, 3, 6, 12, 24, 48, 72, 168, 336, current]).filter { (1...336).contains($0) }).sorted()
    }

    private func settingsSection(_ settings: PaymentSettings) -> some View {
        Section {
            Toggle(tr("Send the bill automatically"), isOn: Binding(
                get: { settings.autoBill },
                set: { on in store.mutateSettings { $0.autoBill = on } }
            ))
            if settings.autoBill {
                Picker(tr("Hours after the session"), selection: Binding(
                    get: { settings.autoBillAfterHours },
                    set: { hours in store.mutateSettings { $0.autoBillAfterHours = hours } }
                )) {
                    ForEach(Self.afterHours(including: settings.autoBillAfterHours), id: \.self) { hours in
                        Text(verbatim: String(hours)).tag(hours)
                    }
                }
            }
            Toggle(tr("Round shares up to the next 10p"), isOn: Binding(
                get: { settings.roundSharesUp },
                set: { on in store.mutateSettings { $0.roundSharesUp = on } }
            ))
        } header: {
            Text(tr("Settings"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if settings.autoBill {
                    Text(tr("If nobody ticks who came, the bill goes to everyone who said they'd come, and whoever scheduled it is told."))
                }
                Text(tr("Shares are easier to type, and anything extra is club income."))
            }
        }
    }
}

// MARK: - Add or change bank details

/// The account number is typed twice — there is no modulus check yet — and
/// the password once, because a live session on a borrowed phone must not be
/// enough to redirect the club's money.
struct BankDetailsForm: View {
    @ObservedObject var store: ClubMoneyStore
    let isChange: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var holder = ""
    @State private var sortCode = ""
    @State private var account = ""
    @State private var accountAgain = ""
    @State private var isPersonal = false
    @State private var password = ""
    @State private var problem: String?
    @State private var passwordProblem: String?
    @FocusState private var passwordFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Account name"), text: $holder)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text(tr("Account name, exactly as on the account"))
                } footer: {
                    Text(tr("Players' banks check this name when they pay (Confirmation of Payee). If it doesn't match, they get a warning, and many will stop."))
                }

                Section {
                    TextField(tr("Sort code"), text: Binding(
                        get: { sortCode },
                        set: { sortCode = BankDetailsCheck.formatSortCode($0) }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    SecureField(tr("Account number"), text: $account)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                    SecureField(tr("Account number again"), text: $accountAgain)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                } header: {
                    Text(tr("Bank details"))
                } footer: {
                    Text(tr("Typed a second time, to catch a wrong digit before anybody pays into it."))
                }

                Section {
                    TextField(tr("Nickname (optional)"), text: $nickname, prompt: Text(tr("Club account")))
                    Toggle(tr("This is a personal account"), isOn: $isPersonal)
                } footer: {
                    Text(tr("Somebody's own account rather than the club's. Players are told."))
                }

                Section {
                    SecureField(tr("Your password"), text: $password)
                        .textContentType(.password)
                        .focused($passwordFocused)
                    if let passwordProblem {
                        Text(passwordProblem).foregroundStyle(FishersTheme.unavailable)
                    }
                } footer: {
                    Text(tr("Typed again, because these details decide where everyone's money goes. If you sign in with Google or Apple, leave it empty."))
                }

                if isChange {
                    Section {
                        Label(tr("A change goes live after 24 hours. Everyone who looks after the club's money is told straight away and can freeze it, in case it wasn't you."), systemImage: "clock")
                            .font(FishersTheme.footnote)
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(isChange ? tr("Change bank details") : tr("Add bank details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isWorking {
                        ProgressView()
                    } else {
                        Button(isChange ? tr("Save the change") : tr("Save bank details")) { Task { await save() } }
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
        }
    }

    private func save() async {
        passwordProblem = nil
        if let local = BankDetailsCheck.problem(holder: holder, sortCode: sortCode, account: account, again: accountAgain) {
            problem = local
            return
        }
        problem = nil
        let label = nickname.trimmingCharacters(in: .whitespaces)
        let outcome = await store.saveBankDetails(NewPayoutAccount(
            holderName: holder.trimmingCharacters(in: .whitespaces),
            sortCode: BankDetailsCheck.digits(sortCode),
            accountNumber: BankDetailsCheck.digits(account),
            label: label.isEmpty ? nil : label,
            isPersonal: isPersonal,
            password: password.isEmpty ? nil : password
        ))
        switch outcome {
        case .saved:
            dismiss()
        case .needsPassword(let message):
            // Not signed out: only the password was wrong or missing.
            passwordProblem = message
            password = ""
            passwordFocused = true
        case .refused(let message):
            problem = message
        }
    }
}

// MARK: - Record cash, or refund credit

struct RecordPaymentSheet: View {
    @ObservedObject var store: ClubMoneyStore
    let action: ClubPaymentsView.PayerAction
    let currency: String

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var method = "cash"
    @State private var note = ""
    @State private var problem: String?

    init(store: ClubMoneyStore, action: ClubPaymentsView.PayerAction, currency: String) {
        self.store = store
        self.action = action
        self.currency = currency
        let start = action.kind == .refund ? action.member.creditCents : action.member.owedCents
        _amount = State(initialValue: start > 0 ? Money.plain(start, currency) : "")
    }

    private var minor: Int? { Money.parse(amount, currency: currency) }
    private var isRefund: Bool { action.kind == .refund }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(isRefund ? tr("Amount to refund") : tr("Amount paid"))
                        Spacer()
                        TextField(tr("Amount"), text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(minHeight: FishersTheme.minTap)
                    if !isRefund {
                        Picker(tr("How they paid"), selection: $method) {
                            Text(tr("Cash")).tag("cash")
                            Text(tr("Bank transfer")).tag("transfer")
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField(tr("Note (optional)"), text: $note)
                } footer: {
                    if isRefund {
                        Text(tr("Record it here once you've sent the money back to {name}. The app doesn't send it.", vars: ["name": action.member.name]))
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(isRefund
                             ? tr("Refund {name}", vars: ["name": action.member.name])
                             : tr("Record a payment from {name}", vars: ["name": action.member.name]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRefund ? tr("Record the refund") : tr("Record it")) { Task { await save() } }
                        .disabled(store.isWorking || (minor ?? 0) <= 0)
                }
            }
        }
    }

    private func save() async {
        guard let minor else { return }
        problem = nil
        let outcome = isRefund
            ? await store.refund(for: action.member, amountCents: minor, note: note)
            : await store.record(for: action.member, amountCents: minor, method: method, note: note)
        if let failure = outcome.failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}

// MARK: - From a notification

/// Where a money notification about a club lands: the overview for a money
/// admin, the pay screen for everybody else. The server decides which, by
/// answering `/clubs/{id}/money` or refusing it.
struct MoneyRouteView: View {
    let clubId: UUID
    /// The pay screen whatever the reader's role — a reminder or a
    /// confirmation is about their own money, even for a treasurer.
    var preferPayScreen = false

    @StateObject private var money: ClubMoneyStore
    @State private var decided = false

    init(clubId: UUID, preferPayScreen: Bool = false) {
        self.clubId = clubId
        self.preferPayScreen = preferPayScreen
        _money = StateObject(wrappedValue: ClubMoneyStore(clubId: clubId))
    }

    var body: some View {
        Group {
            if preferPayScreen {
                PayScreenView(clubId: clubId)
            } else if !decided {
                ProgressView()
            } else if money.forbidden || money.overview == nil {
                PayScreenView(clubId: clubId)
            } else {
                ClubPaymentsView(store: money)
                    .navigationTitle(tr("Payments"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink(tr("Pay")) { PayScreenView(clubId: clubId) }
                        }
                    }
            }
        }
        .task {
            guard !preferPayScreen, !decided else { return }
            await money.load()
            decided = true
        }
    }
}

/// The screen a `MoneyRoute` names.
struct MoneyDestination: View {
    let route: MoneyRoute

    var body: some View {
        switch route {
        case .event(let id, let whoCame):
            EventDetailView(eventId: id, openWhoCame: whoCame)
        case .payScreen(let clubId):
            MoneyRouteView(clubId: clubId, preferPayScreen: true)
        case .overview(let clubId):
            MoneyRouteView(clubId: clubId)
        }
    }
}
