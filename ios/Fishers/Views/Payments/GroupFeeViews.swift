import SwiftUI

/// Payments → Group fees, for money admins: a charge to a group of people
/// that isn't for one session. League registration, a tour, kit, match balls.
struct GroupFeesView: View {
    @StateObject private var store: GroupFeesStore
    @State private var making = false

    init(clubId: UUID, currency: String) {
        _store = StateObject(wrappedValue: GroupFeesStore(clubId: clubId, currency: currency))
    }

    var body: some View {
        List {
            if let notice = store.notice {
                Section { Label(notice, systemImage: "info.circle").font(FishersTheme.subhead) }
            }
            Section {
                Button {
                    making = true
                } label: {
                    Label(tr("New group fee"), systemImage: "plus.circle.fill")
                        .font(FishersTheme.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.pitch)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(tr("Everyone in it is told what they owe and pays the same way as for a session."))
            }
            if store.hasLoaded, store.fees.isEmpty {
                Section {
                    Text(tr("No group fees yet. Use one for league fees, a tour, kit or match balls."))
                        .foregroundStyle(.secondary)
                }
            }
            if !store.fees.isEmpty {
                Section(tr("Recent")) {
                    ForEach(store.fees) { fee in
                        NavigationLink {
                            GroupFeeDetailView(fee: fee)
                        } label: {
                            GroupFeeRow(fee: fee)
                        }
                    }
                }
            }
            if !store.hasLoaded {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle(tr("Group fees"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $making, onDismiss: { Task { await store.load() } }) {
            NewGroupFeeSheet(store: store)
        }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct GroupFeeRow: View {
    let fee: GroupFee

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(fee.titleWithDue)
                    .font(FishersTheme.subhead.weight(.medium))
                    .strikethrough(fee.isCancelled)
                Spacer()
                Text(Money.format(fee.totalCents, fee.currency))
                    .font(FishersTheme.subhead.monospacedDigit())
            }
            Text(fee.summary)
                .font(FishersTheme.footnote)
                .foregroundStyle(fee.isCancelled ? .secondary : (fee.owedCents > 0 ? FishersTheme.unavailable : FishersTheme.available))
        }
        .frame(minHeight: FishersTheme.minTap)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One group fee

struct GroupFeeDetailView: View {
    @StateObject private var store: GroupFeeStore
    @State private var cancelling = false
    @State private var cancelReason = ""

    init(fee: GroupFee) {
        _store = StateObject(wrappedValue: GroupFeeStore(billId: fee.id, fee: fee))
    }

    /// From the payments overview, which knows only the bill.
    init(billId: UUID) {
        _store = StateObject(wrappedValue: GroupFeeStore(billId: billId))
    }

    var body: some View {
        List {
            if let fee = store.fee {
                if let notice = store.notice {
                    Section { Label(notice, systemImage: "info.circle").font(FishersTheme.subhead) }
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("{paid} of {total} collected", vars: [
                            "paid": Money.format(fee.paidCents, fee.currency),
                            "total": Money.format(fee.totalCents, fee.currency),
                        ]))
                        .font(FishersTheme.headline)
                        Text(fee.summary)
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                        // "Split between whoever comes" is a session's words.
                        if fee.mode == .perPlayer {
                            Text(tr("{amount} each", vars: ["amount": Money.format(fee.amountCents, fee.currency)]))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let due = DayDate.short(fee.dueOn) {
                            Text(tr("Due by {date}", vars: ["date": due]))
                                .font(FishersTheme.footnote)
                        }
                        if let note = fee.note {
                            Text(tr("Note: {note}", vars: ["note": note]))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                if !fee.isCancelled {
                    Section {
                        BillShareBlock(
                            anyoneOwes: fee.owedCents > 0,
                            linkIsOpen: store.linkKnown ? store.link != nil : nil,
                            makeLink: { await store.billLink() },
                            switchOff: { await store.switchLinkOff() }
                        )
                        .padding(.vertical, 4)
                    }
                }
                if !fee.shares.isEmpty {
                    Section(tr("Who's in it")) {
                        ForEach(fee.shares) { share in
                            ShareLine(share: share, showsName: true)
                        }
                    }
                }
                if !fee.isCancelled {
                    Section {
                        Button(tr("Cancel this group fee"), role: .destructive) { cancelling = true }
                            .frame(minHeight: FishersTheme.minTap)
                    } footer: {
                        Text(tr("Everyone in it is told. Anything already paid towards it becomes credit."))
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .disabled(store.isWorking)
        .navigationTitle(store.fee?.title ?? tr("Group fees"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .task { await store.loadLink() }
        .refreshable { await store.load() }
        .alert(tr("Why is it being cancelled?"), isPresented: $cancelling) {
            TextField(tr("Say why, in a few words."), text: $cancelReason)
            Button(tr("Cancel it"), role: .destructive) {
                let reason = cancelReason.trimmingCharacters(in: .whitespacesAndNewlines)
                cancelReason = ""
                Task { await store.cancel(reason: reason) }
            }
            .disabled(cancelReason.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(tr("Never mind"), role: .cancel) { cancelReason = "" }
        } message: {
            Text(tr("Everyone in it is told. Anything already paid towards it becomes credit."))
        }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

// MARK: - New group fee

/// Who, how much, by when. Then share it to WhatsApp straight away.
struct NewGroupFeeSheet: View {
    @ObservedObject var store: GroupFeesStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft = GroupFeeDraft()
    @State private var newGuest = ""
    @State private var problem: String?
    @State private var made: GroupFee?

    private var currency: String { store.currency }

    var body: some View {
        NavigationStack {
            Group {
                if let made {
                    GroupFeeSentView(fee: made) { dismiss() }
                } else {
                    form
                }
            }
            .navigationTitle(made == nil ? tr("New group fee") : tr("Group fee sent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if made == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("sc.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if store.isWorking {
                            ProgressView()
                        } else {
                            Button(tr("Send")) { Task { await save() } }
                        }
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
        }
    }

    private var form: some View {
        Form {
            Section(tr("What's it for?")) {
                TextField(tr("League registration"), text: $draft.title)
                    .textInputAutocapitalization(.sentences)
            }

            Section {
                Picker(tr("Who pays?"), selection: $draft.who) {
                    Text(tr("Everyone in the club")).tag(GroupFeeWho.everyone)
                    ForEach(store.teams) { team in
                        Text(tr("The {team} team", vars: ["team": team.name])).tag(GroupFeeWho.team(team.id))
                    }
                    ForEach(store.groups.inUse.filter { !$0.forGuests }) { group in
                        Text(tr("Everyone on the {group} price", vars: ["group": group.name])).tag(GroupFeeWho.group(group.id))
                    }
                    Text(tr("Names I pick")).tag(GroupFeeWho.people)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(tr("Who pays?"))
            }

            if draft.who == .people {
                Section {
                    ForEach(store.members) { member in
                        Toggle(member.name, isOn: Binding(
                            get: { draft.picked.contains(member.userId) },
                            set: { on in
                                if on { draft.picked.insert(member.userId) } else { draft.picked.remove(member.userId) }
                            }
                        ))
                        .frame(minHeight: FishersTheme.minTap)
                    }
                } header: {
                    Text(tr("Tick who it's for"))
                }
            }

            Section {
                ForEach(draft.guests, id: \.self) { Text($0) }
                    .onDelete { draft.guests.remove(atOffsets: $0) }
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
                Text(tr("Somebody who isn't in the club. Share the pay link with them on WhatsApp."))
            }

            Section {
                Picker(tr("How much"), selection: $draft.mode) {
                    Text(tr("Same from each")).tag(CostMode.perPlayer)
                    Text(tr("Split a total")).tag(CostMode.splitTotal)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(Money.format(0, currency).prefix { !$0.isNumber })
                        .foregroundStyle(.secondary)
                    TextField(draft.mode == .splitTotal ? tr("Total to split") : tr("Each person pays"), text: $draft.amount)
                        .keyboardType(.decimalPad)
                }
                .frame(minHeight: FishersTheme.minTap)
            } header: {
                Text(tr("How much"))
            } footer: {
                Text(draft.mode == .splitTotal
                     ? tr("The total is shared between everyone in it.")
                     : tr("Everyone in it pays this."))
            }

            Section {
                Toggle(tr("Pay by a date"), isOn: $draft.hasDueDate)
                    .frame(minHeight: FishersTheme.minTap)
                if draft.hasDueDate {
                    DatePicker(tr("Due by"), selection: $draft.dueOn, in: Date.now..., displayedComponents: .date)
                }
            }

            Section(tr("A note for everyone (optional)")) {
                TextField(tr("Includes the umpires' fee"), text: $draft.note, axis: .vertical)
                    .lineLimit(1...3)
            }

            if let problem {
                Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
            }
        }
        .disabled(store.isWorking)
    }

    private func addGuest() {
        let name = newGuest.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty else { return }
        if !draft.guests.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            draft.guests.append(name)
        }
        newGuest = ""
    }

    private func save() async {
        if let local = draft.problem(currency: currency) {
            problem = local
            return
        }
        guard let body = draft.body(currency: currency) else { return }
        problem = nil
        let (outcome, fee) = await store.create(body)
        if let failure = outcome.failure {
            problem = failure
        } else if let fee {
            made = fee
        } else {
            dismiss()
        }
    }
}

/// Sent: say so, and offer the one obvious next step.
private struct GroupFeeSentView: View {
    @StateObject private var store: GroupFeeStore
    let done: () -> Void

    init(fee: GroupFee, done: @escaping () -> Void) {
        _store = StateObject(wrappedValue: GroupFeeStore(billId: fee.id, fee: fee))
        self.done = done
    }

    var body: some View {
        Form {
            if let fee = store.fee {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(fee.people == 1
                              ? tr("Sent to 1 person.")
                              : tr("Sent to {n} people.", vars: ["n": fee.people]),
                              systemImage: "checkmark.seal.fill")
                            .font(FishersTheme.headline)
                            .foregroundStyle(FishersTheme.available)
                        Text(tr("Now share it to WhatsApp: everyone taps the link and pays, with no app and no password."))
                            .font(FishersTheme.subhead)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    BillShareBlock(
                        anyoneOwes: fee.owedCents > 0,
                        makeLink: { await store.billLink() },
                        switchOff: { await store.switchLinkOff() }
                    )
                    .padding(.vertical, 4)
                }
            }
            if let notice = store.notice {
                Section { Label(notice, systemImage: "info.circle").font(FishersTheme.subhead) }
            }
            if let error = store.errorMessage {
                Section { Text(error).foregroundStyle(FishersTheme.unavailable) }
            }
            Section {
                Button(action: done) {
                    Text(tr("Done"))
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.bordered)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }
}
