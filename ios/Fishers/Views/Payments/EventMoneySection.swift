import SwiftUI

/// The money on one fixture or nets session: its cost, who came, the bill,
/// and the reader's own share.
///
/// What each person sees is decided by the flags the API sends — `can_bill`,
/// `can_manage_money`, `my_share` — never by working out roles here.
struct EventMoneySection: View {
    @ObservedObject var store: EventMoneyStore
    let event: Event
    /// Arrived from "Who came to Friday nets?": open the ticking straight away.
    var openWhoCame = false

    @State private var editingCost = false
    @State private var whoCame: WhoCameMode?
    @State private var confirmRemoveCost = false
    @State private var cancelling = false
    @State private var cancelReason = ""
    @State private var lettingOff: ClubShare?
    @State private var letOffReason = ""
    @State private var openedOnce = false
    @State private var tickingCash = false

    enum WhoCameMode: Identifiable {
        case send
        case resplit(version: Int)

        var id: String {
            switch self {
            case .send: return "send"
            case .resplit(let v): return "resplit-\(v)"
            }
        }

        var version: Int? {
            if case .resplit(let v) = self { return v }
            return nil
        }
    }

    var body: some View {
        if let page = store.page, page.isRelevant {
            VStack(alignment: .leading, spacing: 12) {
                Label(tr("Money"), systemImage: "banknote")
                    .font(FishersTheme.headline)
                if let notice = store.notice {
                    Label(notice, systemImage: "info.circle")
                        .font(FishersTheme.footnote)
                        .foregroundStyle(FishersTheme.maybe)
                }
                costBlock(page)
                if let bill = page.bill {
                    billBlock(page, bill)
                } else if page.cost != nil, page.canBill {
                    whoCameBlock(page)
                }
                if let mine = page.myShare {
                    myShareBlock(page, mine)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: FishersTheme.corner))
            .disabled(store.isWorking)
            .sheet(isPresented: $editingCost) {
                CostEditorSheet(store: store, page: page, event: event)
            }
            .sheet(item: $whoCame) { mode in
                WhoCameSheet(store: store, page: page, version: mode.version)
            }
            .sheet(isPresented: $tickingCash) {
                CashChecklistSheet(store: store, shares: stillOwing(page), countsAsPaid: page.canManageMoney)
            }
            .confirmationDialog(tr("Remove the cost"), isPresented: $confirmRemoveCost, titleVisibility: .hidden) {
                Button(tr("Remove the cost"), role: .destructive) { Task { await store.removeCost() } }
                Button(tr("Never mind"), role: .cancel) {}
            }
            .alert(tr("Why is the bill being cancelled?"), isPresented: $cancelling) {
                TextField(tr("Say why, in a few words."), text: $cancelReason)
                Button(tr("Cancel the bill"), role: .destructive) {
                    let reason = cancelReason
                    cancelReason = ""
                    Task { await store.void(reason: reason) }
                }
                .disabled(cancelReason.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(tr("Never mind"), role: .cancel) { cancelReason = "" }
            } message: {
                Text(tr("Everyone on it is told. Anything already paid towards it becomes credit."))
            }
            .alert(
                tr("Why is {name} being let off?", vars: ["name": lettingOff?.name ?? ""]),
                isPresented: Binding(get: { lettingOff != nil }, set: { if !$0 { lettingOff = nil } })
            ) {
                TextField(tr("Say why, in a few words."), text: $letOffReason)
                Button(tr("Let off")) {
                    guard let share = lettingOff else { return }
                    let reason = letOffReason
                    letOffReason = ""
                    Task { await store.waive(share, reason: reason) }
                }
                .disabled(letOffReason.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(tr("Never mind"), role: .cancel) { letOffReason = "" }
            } message: {
                Text(tr("A junior, a coach, hardship. Only the club's money admins see this."))
            }
            .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
                Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .onAppear {
                guard openWhoCame, !openedOnce else { return }
                openedOnce = true
                if page.canBill, page.cost != nil, page.bill == nil { whoCame = .send }
            }
        }
    }

    // MARK: Cost

    @ViewBuilder
    private func costBlock(_ page: EventBillPage) -> some View {
        if let cost = page.cost {
            VStack(alignment: .leading, spacing: 4) {
                Text(cost.summary)
                    .font(FishersTheme.subhead.weight(.semibold))
                if !page.prices.isEmpty {
                    Text(page.prices.map { $0.describe(cost.currency) }.joined(separator: " · "))
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
                if let note = cost.note {
                    Text(note).font(FishersTheme.footnote).foregroundStyle(.secondary)
                }
                if page.canBill, !page.hasPayoutAccount {
                    Text(tr("The club hasn't added bank details yet. Players will see what they owe, but can't pay by transfer until somebody adds them."))
                        .font(FishersTheme.footnote)
                        .foregroundStyle(FishersTheme.maybe)
                }
            }
            if page.canBill, page.bill == nil {
                ButtonRow {
                    Button(tr("Change the cost")) { editingCost = true }
                        .buttonStyle(.bordered)
                    Button(tr("Remove"), role: .destructive) { confirmRemoveCost = true }
                        .buttonStyle(.bordered)
                }
            }
        } else if page.canBill, page.bill == nil {
            Text(tr("No cost on this one. Add one and the app splits it between whoever came."))
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            Button {
                editingCost = true
            } label: {
                Label(tr("Add a cost"), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Who came

    private func whoCameBlock(_ page: EventBillPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isOver(page)
                 ? tr("Tick everyone who came. Each person is sent their share and the club's bank details.")
                 : tr("Once it's over, tick who came and send the bill."))
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            Button {
                whoCame = .send
            } label: {
                Label(tr("Who came?"), systemImage: "checklist")
                    .font(FishersTheme.headline)
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.pitch)
        }
    }

    private func isOver(_ page: EventBillPage) -> Bool {
        (page.endAt ?? event.endAt) <= .now
    }

    // MARK: The bill

    /// What hasn't come in yet, naming only the parts there are.
    private func stillToCome(_ bill: EventBill) -> String? {
        let waiting = Money.format(bill.waitingCents, bill.currency)
        let owed = Money.format(bill.owedCents, bill.currency)
        switch (bill.waitingCents > 0, bill.owedCents > 0) {
        case (true, true): return tr("{waiting} waiting to be checked · {owed} still owed", vars: ["waiting": waiting, "owed": owed])
        case (false, true): return tr("{amount} still owed", vars: ["amount": owed])
        case (true, false): return tr("{amount} to check", vars: ["amount": waiting])
        case (false, false): return nil
        }
    }

    @ViewBuilder
    private func billBlock(_ page: EventBillPage, _ bill: EventBill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("{paid} of {total} collected", vars: [
                "paid": Money.format(bill.paidCents, bill.currency),
                "total": Money.format(bill.totalCents, bill.currency),
            ]))
            .font(FishersTheme.subhead.weight(.semibold))
            // Only the parts there are: not "£0.00 waiting to be checked".
            if let left = stillToCome(bill) {
                Text(left)
                    .font(FishersTheme.footnote)
                    .foregroundStyle(bill.owedCents > 0 ? FishersTheme.unavailable : FishersTheme.maybe)
            }
            if bill.surplusCents > 0 {
                Text(tr("Shares are rounded up, so {amount} extra goes to the club.", vars: ["amount": Money.format(bill.surplusCents, bill.currency)]))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
            if let note = bill.note {
                Text(tr("Note: {note}", vars: ["note": note])).font(FishersTheme.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)

        if page.canBill || page.canManageMoney, !page.shares.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(page.shares) { share in
                    HStack(spacing: 8) {
                        ShareLine(share: share, showsName: true)
                        if page.canManageMoney, share.state.canBeLetOff {
                            Button(tr("Let off")) { lettingOff = share }
                                .font(FishersTheme.footnote)
                                .buttonStyle(.bordered)
                                .frame(minHeight: FishersTheme.minTap)
                                .accessibilityLabel(tr("Let {name} off", vars: ["name": share.name]))
                        }
                    }
                    Divider()
                }
            }
        }

        if page.canBill {
            if !stillOwing(page).isEmpty {
                Button {
                    tickingCash = true
                } label: {
                    Label(tr("Who paid cash?"), systemImage: "banknote")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.bordered)
            }
            BillShareBlock(store: store, anyoneOwes: bill.owedCents > 0)
                .padding(.top, 4)
            ButtonRow {
                Button(tr("Change who came")) { whoCame = .resplit(version: bill.version) }
                    .buttonStyle(.bordered)
                Button(tr("Cancel the bill"), role: .destructive) { cancelling = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// Who still has something to pay on the bill, for "Who paid cash?".
    private func stillOwing(_ page: EventBillPage) -> [ClubShare] {
        page.shares.filter { $0.state.stillOwed && $0.leftCents > 0 }
    }

    // MARK: The reader's own share

    private func myShareBlock(_ page: EventBillPage, _ mine: ClubShare) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Your share"))
                    .font(FishersTheme.subhead)
                Spacer()
                Text(Money.format(mine.amountCents, mine.currency))
                    .font(FishersTheme.figure(.title3))
                ShareStateBadge(state: mine.state)
            }
            .accessibilityElement(children: .combine)
            if mine.state.stillOwed {
                NavigationLink {
                    PayScreenView(clubId: page.clubId)
                } label: {
                    Label(tr("Pay"), systemImage: "arrow.right.circle.fill")
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.pitch)
            } else if mine.state == .waiting {
                Text(tr("Waiting for the club to confirm"))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(FishersTheme.maybe)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Who came?

/// Tick who came, add guests, see the split, send. A re-split starts from
/// who is on the bill now and sends its version, so two people changing it
/// at once cannot quietly overwrite each other.
struct WhoCameSheet: View {
    @ObservedObject var store: EventMoneyStore
    let page: EventBillPage
    /// Set when re-splitting a bill already sent.
    let version: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var ticked: Set<UUID>
    @State private var guests: [String]
    @State private var newGuest = ""
    @State private var note = ""
    @State private var preview: BillPreview?
    @State private var previewProblem: String?
    @State private var problem: String?

    init(store: EventMoneyStore, page: EventBillPage, version: Int?) {
        self.store = store
        self.page = page
        self.version = version
        _ticked = State(initialValue: version == nil ? page.suggestedMembers : page.billedMembers)
        _guests = State(initialValue: page.guests)
    }

    private var invited: [BillCandidate] { page.candidates.filter(\.wasInvited) }
    private var others: [BillCandidate] { page.candidates.filter { !$0.wasInvited } }

    private var body_: BillBody {
        BillBody(
            attendees: ticked.sorted { $0.uuidString < $1.uuidString },
            guests: guests,
            version: version,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
    }

    /// What the preview depends on; the note does not change a penny.
    private struct PreviewKey: Hashable {
        let ticked: Set<UUID>
        let guests: [String]
    }

    var body: some View {
        NavigationStack {
            Form {
                if !invited.isEmpty {
                    Section {
                        ForEach(invited) { row($0) }
                    } footer: {
                        Text(version == nil
                             ? tr("Tick everyone who came. Each person is sent their share and the club's bank details.")
                             : tr("Add or take people off and the bill is split again. Anything already paid moves to the new share."))
                    }
                }
                if !others.isEmpty {
                    Section(tr("Others in the club")) {
                        ForEach(others) { row($0) }
                    }
                }

                Section {
                    ForEach(guests, id: \.self) { guest in
                        Text(guest)
                    }
                    .onDelete { guests.remove(atOffsets: $0) }
                    HStack {
                        TextField(tr("Add a guest"), text: $newGuest)
                            .textInputAutocapitalization(.words)
                            .onSubmit(addGuest)
                        Button(tr("Add"), action: addGuest)
                            .disabled(newGuest.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(minHeight: FishersTheme.minTap)
                } header: {
                    Text(tr("Guests"))
                } footer: {
                    Text(tr("Somebody who isn't in the club"))
                }

                Section(tr("A note for everyone (optional)")) {
                    TextField(tr("The venue still charged us, even though it rained"), text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    if let preview {
                        Text(preview.summary)
                            .font(FishersTheme.headline)
                        if preview.surplusCents > 0 {
                            Text(tr("Shares are rounded up, so {amount} extra goes to the club.", vars: ["amount": Money.format(preview.surplusCents, preview.currency)]))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(preview.coveredLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline) {
                                Text(line.name)
                                Spacer()
                                Text(line.covered ?? "")
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(FishersTheme.available)
                                    .multilineTextAlignment(.trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } else if let previewProblem {
                        Text(previewProblem).foregroundStyle(FishersTheme.unavailable)
                    } else {
                        ProgressView()
                    }
                } header: {
                    Text(tr("Total"))
                } footer: {
                    if let cost = page.cost { Text(cost.summary) }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(version == nil ? tr("Who came?") : tr("Change who came"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(version == nil ? tr("Send the bill") : tr("Split the bill again")) {
                        Task { await send() }
                    }
                    .disabled(store.isWorking || preview == nil)
                }
            }
            .interactiveDismissDisabled(store.isWorking)
            .task(id: PreviewKey(ticked: ticked, guests: guests)) {
                // One request after the ticking stops, not one per tap.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await refreshPreview()
            }
        }
    }

    private func row(_ candidate: BillCandidate) -> some View {
        Toggle(isOn: Binding(
            get: { ticked.contains(candidate.userId) },
            set: { on in
                if on { ticked.insert(candidate.userId) } else { ticked.remove(candidate.userId) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                if let answer = candidate.answer {
                    Text(answer).font(FishersTheme.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: FishersTheme.minTap)
    }

    private func addGuest() {
        let name = newGuest.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty else { return }
        if !guests.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            guests.append(name)
        }
        newGuest = ""
    }

    private func refreshPreview() async {
        switch await store.preview(body_) {
        case .ready(let fresh):
            preview = fresh
            previewProblem = nil
        case .refused(let message):
            preview = nil
            previewProblem = message
        }
    }

    private func send() async {
        problem = nil
        // Sent, or somebody else changed it first: either way the section
        // behind has reloaded and says which, so the sheet goes.
        if let failure = await store.send(body_).failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}

// MARK: - Cost

/// Set or change an event's cost while it is unbilled.
struct CostEditorSheet: View {
    @ObservedObject var store: EventMoneyStore
    let page: EventBillPage
    let event: Event

    @Environment(\.dismiss) private var dismiss
    @State private var mode: CostMode
    @State private var amount: String
    @State private var note: String
    @State private var applyToSeries = false
    @State private var confirmBig = false
    @State private var problem: String?
    /// The club's groups that pay their own price, for "Different price for
    /// juniors?". Empty, and no question, for a club with none.
    @State private var groups: [PriceType] = []
    @State private var prices: SessionPricesDraft

    init(store: EventMoneyStore, page: EventBillPage, event: Event) {
        self.store = store
        self.page = page
        self.event = event
        let currency = page.cost?.currency ?? event.feeCurrency
        let existing = page.cost
        _mode = State(initialValue: existing.map { $0.mode == .perPlayer ? .perPlayer : .splitTotal } ?? .splitTotal)
        _amount = State(initialValue: existing.map { Money.plain($0.amountCents, currency) } ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _prices = State(initialValue: SessionPricesDraft(existing: page.prices, currency: currency))
    }

    private var currency: String { page.cost?.currency ?? event.feeCurrency }
    private var minor: Int? { Money.parse(amount, currency: currency) }
    private var isSeries: Bool { event.metadata?["series_id"] != nil }

    var body: some View {
        NavigationStack {
            Form {
                CostFields(mode: $mode, amount: $amount, currency: currency)

                if mode == .perPlayer, !groups.isEmpty {
                    groupPricesSection
                }

                Section(tr("Note (optional)")) {
                    TextField(tr("Two lanes for two hours"), text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if isSeries {
                    Section {
                        Toggle(tr("Also the later weeks"), isOn: $applyToSeries)
                    } footer: {
                        Text(tr("Every later week of this series that hasn't been billed yet gets the same cost."))
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(page.cost == nil ? tr("Add a cost") : tr("Change the cost"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save")) {
                        if mode == .perPlayer, let minor, minor > Money.confirmAboveMinor {
                            confirmBig = true
                        } else {
                            Task { await save() }
                        }
                    }
                    .disabled(store.isWorking || (minor ?? 0) <= 0)
                }
            }
            .task { groups = await store.priceGroups(clubId: page.clubId) }
            .confirmationDialog(
                tr("{amount} each", vars: ["amount": Money.format(minor ?? 0, currency)]),
                isPresented: $confirmBig, titleVisibility: .visible
            ) {
                Button(tr("Yes, {amount} each is right", vars: ["amount": Money.format(minor ?? 0, currency)])) {
                    Task { await save() }
                }
                Button(tr("Never mind"), role: .cancel) {}
            } message: {
                Text(tr("That's a lot a head, so it's worth a second look before anybody is asked for it."))
            }
        }
    }

    /// "Different price for juniors?": a price for each group, or empty
    /// for the usual one.
    private var groupPricesSection: some View {
        Section {
            Toggle(tr("Different price for juniors?"), isOn: $prices.on)
                .frame(minHeight: FishersTheme.minTap)
            if prices.on {
                ForEach(groups) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text(Money.format(0, currency).prefix { !$0.isNumber })
                            .foregroundStyle(.secondary)
                        TextField(tr("Usual price"), text: Binding(
                            get: { prices.typed[group.id] ?? "" },
                            set: { prices.typed[group.id] = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                    }
                    .frame(minHeight: FishersTheme.minTap)
                }
            }
        } footer: {
            Text(prices.on
                 ? tr("Leave one empty for the usual price. Put 0 to make it free for them.")
                 : tr("Juniors, students or guests can pay a different price for this session."))
        }
    }

    private func save() async {
        guard let minor else { return }
        problem = nil
        let typed = prices.body(mode: mode, groups: groups, existing: page.prices, currency: currency)
        if let wrong = typed.problem {
            problem = wrong
            return
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = await store.setCost(
            mode: mode, amountCents: minor, note: trimmed.isEmpty ? nil : trimmed, applyToSeries: applyToSeries,
            prices: typed.prices
        )
        if let failure = outcome.failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}

/// "Split a total" or "Same for everyone", and the amount. Shared by the
/// cost editor and the schedule form.
struct CostFields: View {
    @Binding var mode: CostMode
    @Binding var amount: String
    let currency: String

    var body: some View {
        Section {
            Picker(tr("How it's paid"), selection: $mode) {
                ForEach(CostMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Text(currencySymbol)
                    .foregroundStyle(.secondary)
                TextField(mode == .splitTotal ? tr("Total to split") : tr("Each person pays"), text: $amount)
                    .keyboardType(.decimalPad)
            }
            .frame(minHeight: FishersTheme.minTap)
        } footer: {
            Text(mode == .splitTotal
                 ? tr("The venue's bill, say. It's shared between whoever comes.")
                 : tr("A match fee, say. Everyone who plays pays the same."))
        }
    }

    private var currencySymbol: String {
        let formatted = Money.format(0, currency)
        return String(formatted.prefix { !$0.isNumber })
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Buttons side by side while they fit, stacked once Dynamic Type makes them
/// too wide — a row that clips "Cancel bill" at the largest sizes hides it.
struct ButtonRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
        .frame(minHeight: FishersTheme.minTap)
    }
}
