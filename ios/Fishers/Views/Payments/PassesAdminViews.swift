import SwiftUI

/// Payments → Passes, for money admins: make a pass from a template, see
/// who's on each and how they stand, add somebody, cancel, keep covering.
struct PassesAdminView: View {
    @StateObject private var store: PassesAdminStore
    @State private var making = false

    init(clubId: UUID, currency: String) {
        _store = StateObject(wrappedValue: PassesAdminStore(clubId: clubId, currency: currency))
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
                    Label(tr("New pass"), systemImage: "plus.circle.fill")
                        .font(FishersTheme.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.pitch)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(tr("Start from a template, then change the numbers. Players on a pass don't pay for the sessions it covers."))
            }
            if store.hasLoaded, store.plans.isEmpty {
                Section {
                    Text(tr("No passes yet."))
                        .foregroundStyle(.secondary)
                }
            }
            if !store.offered.isEmpty {
                Section(tr("Offered")) {
                    ForEach(store.offered) { plan in
                        NavigationLink {
                            PassDetailAdminView(store: store, planId: plan.id)
                        } label: {
                            PassPlanRow(plan: plan, groups: store.groups)
                        }
                    }
                }
            }
            if !store.stopped.isEmpty {
                Section(tr("No longer offered")) {
                    ForEach(store.stopped) { plan in
                        NavigationLink {
                            PassDetailAdminView(store: store, planId: plan.id)
                        } label: {
                            PassPlanRow(plan: plan, groups: store.groups)
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
        .navigationTitle(tr("Passes"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $making) { NewPassSheet(store: store) }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

/// A pass in a list: what it costs, what it covers, how many are on it.
struct PassPlanRow: View {
    let plan: PassPlan
    let groups: [PriceType]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(plan.name).font(FishersTheme.subhead.weight(.semibold))
            Text(plan.priceWords).font(FishersTheme.footnote)
            Text(plan.coverWords)
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(onIt)
                .font(FishersTheme.footnote)
                .foregroundStyle(FishersTheme.pitch)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var onIt: String {
        var parts = [plan.holders == 0 ? tr("Nobody yet.")
                     : plan.holders == 1 ? tr("1 person on it") : tr("{n} people on it", vars: ["n": plan.holders])]
        if let only = plan.onlyFor(groups) { parts.append(only) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - One pass

struct PassDetailAdminView: View {
    @ObservedObject var store: PassesAdminStore
    let planId: UUID

    @State private var adding = false
    @State private var cancelling: PassHolder?
    @State private var confirmStop = false

    private var plan: PassPlan? { store.plans.first { $0.id == planId } }
    private var holders: [PassHolder] { store.holders[planId] ?? [] }

    var body: some View {
        List {
            if let plan {
                if let notice = store.notice {
                    Section { Label(notice, systemImage: "info.circle").font(FishersTheme.subhead) }
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.priceWords).font(FishersTheme.headline)
                        Text(plan.coverWords)
                            .font(FishersTheme.subhead)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let only = plan.onlyFor(store.groups) {
                            Text(only).font(FishersTheme.footnote).foregroundStyle(FishersTheme.maybe)
                        }
                    }
                    .padding(.vertical, 4)
                }
                holdersSection(plan)
                settingsSection(plan)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .disabled(store.isWorking)
        .navigationTitle(plan?.name ?? tr("Passes"))
        .navigationBarTitleDisplayMode(.inline)
        .task { if let plan { await store.loadHolders(plan) } }
        .refreshable {
            await store.load()
            if let plan { await store.loadHolders(plan) }
        }
        .sheet(isPresented: $adding) {
            if let plan { AddToPassSheet(store: store, plan: plan, onIt: Set(holders.filter { !$0.isCancelled }.map(\.userId))) }
        }
        .confirmationDialog(
            tr("Cancel {name}'s pass?", vars: ["name": cancelling?.name ?? ""]),
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible,
            presenting: cancelling
        ) { holder in
            Button(tr("Yes, cancel it"), role: .destructive) {
                guard let plan else { return }
                Task { await store.cancel(holder, on: plan) }
            }
            Button(tr("Never mind"), role: .cancel) {}
        } message: { holder in
            Text(holder.billing == .monthly
                 ? tr("It covers them to the end of the month already charged. They're reminded to cancel their standing order.")
                 : tr("It stops covering them today. Anything already charged stays as it is."))
        }
        .confirmationDialog(tr("Stop offering this pass?"), isPresented: $confirmStop, titleVisibility: .visible) {
            Button(tr("Stop offering it"), role: .destructive) {
                guard let plan else { return }
                Task { await store.stopOffering(plan) }
            }
            Button(tr("Never mind"), role: .cancel) {}
        } message: {
            Text(tr("Nobody new can get it. Anyone on it now stays on it until they or you cancel."))
        }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: Who's on it

    private func holdersSection(_ plan: PassPlan) -> some View {
        Section {
            if holders.isEmpty {
                Text(tr("Nobody yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(holders) { holder in
                VStack(alignment: .leading, spacing: 6) {
                    Text(holder.name).font(FishersTheme.subhead.weight(.semibold))
                    Text(holder.adminStanding)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(colour(holder))
                    if let next = DayDate.short(holder.nextChargeOn), !holder.isCancelled {
                        Text(tr("Next payment {date}", vars: ["date": next]))
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !holder.isCancelled {
                        if holder.standing != .upToDate || holder.keepCovering {
                            Toggle(tr("Keep covering"), isOn: Binding(
                                get: { holder.keepCovering },
                                set: { on in Task { await store.keepCovering(holder, on: plan, on) } }
                            ))
                            .frame(minHeight: FishersTheme.minTap)
                        }
                        Button(tr("Cancel their pass"), role: .destructive) { cancelling = holder }
                            .buttonStyle(.borderless)
                            .frame(minHeight: FishersTheme.minTap)
                    }
                }
                .padding(.vertical, 2)
            }
            if !plan.isArchived {
                Button {
                    adding = true
                } label: {
                    Label(tr("Add somebody"), systemImage: "person.badge.plus")
                        .frame(minHeight: FishersTheme.minTap)
                }
            }
        } header: {
            Text(tr("Who's on it"))
        } footer: {
            if holders.contains(where: { $0.standing != .upToDate && !$0.isCancelled }) {
                Text(tr("Keep covering: their pass goes on covering sessions even though a payment is missing."))
            }
        }
    }

    private func colour(_ holder: PassHolder) -> Color {
        if holder.isCancelled { return .secondary }
        switch holder.standing {
        case .upToDate: return FishersTheme.available
        case .behind: return FishersTheme.maybe
        case .suspended: return holder.keepCovering ? FishersTheme.maybe : FishersTheme.unavailable
        case .unknown: return .secondary
        }
    }

    // MARK: Offering it

    private func settingsSection(_ plan: PassPlan) -> some View {
        Section {
            if !plan.isArchived {
                Toggle(tr("Players can get it themselves"), isOn: Binding(
                    get: { plan.openToJoin },
                    set: { on in Task { await store.setOpen(plan, on) } }
                ))
                .frame(minHeight: FishersTheme.minTap)
                Button(tr("Stop offering it"), role: .destructive) { confirmStop = true }
                    .frame(minHeight: FishersTheme.minTap)
            } else {
                Button(tr("Offer it again")) { Task { await store.offerAgain(plan) } }
                    .frame(minHeight: FishersTheme.minTap)
            }
        } footer: {
            Text(plan.openToJoin
                 ? tr("Players see it on the club's pay screen and can get it there.")
                 : tr("Only you and the club's other money admins can put people on it."))
        }
    }
}

// MARK: - Add somebody

struct AddToPassSheet: View {
    @ObservedObject var store: PassesAdminStore
    let plan: PassPlan
    /// Already on it.
    let onIt: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var problem: String?

    private var members: [ClubMemberDetail] {
        store.members.filter { !onIt.contains($0.userId) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
                Section {
                    ForEach(members) { member in
                        Button {
                            Task { await add(member) }
                        } label: {
                            HStack {
                                Text(member.name).foregroundStyle(Color.primary)
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(FishersTheme.pitch)
                            }
                            .frame(minHeight: FishersTheme.minTap)
                        }
                    }
                } footer: {
                    Text(tr("Their first payment is added to what they owe straight away. If they've paid you already, record it under Who owes what."))
                }
            }
            .searchable(text: $search)
            .disabled(store.isWorking)
            .navigationTitle(tr("Add to {pass}", vars: ["pass": plan.name]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
            }
        }
    }

    private func add(_ member: ClubMemberDetail) async {
        problem = nil
        if let failure = await store.add(member, to: plan).failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}

// MARK: - New pass

/// Pick a template, change the numbers, save.
struct NewPassSheet: View {
    @ObservedObject var store: PassesAdminStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PassDraft?
    @State private var problem: String?

    private var currency: String { store.currency }

    var body: some View {
        NavigationStack {
            Form {
                if draft == nil {
                    templates
                } else {
                    form
                    if let problem {
                        Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                    }
                }
            }
            .navigationTitle(tr("New pass"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                if draft != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if store.isWorking {
                            ProgressView()
                        } else {
                            Button(tr("Save")) { Task { await save() } }
                        }
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
        }
    }

    // MARK: Step 1

    private var templates: some View {
        Section {
            ForEach(PassTemplate.allCases) { template in
                Button {
                    draft = template.draft(currency: currency, groups: store.groups)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: template.symbol)
                            .font(.title2)
                            .foregroundStyle(FishersTheme.pitch)
                            .frame(width: 44, height: 44)
                            .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                        // Colours, not .primary/.secondary: inside a button
                        // those are shades of the tint, and the blurb came
                        // out pale green on white.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(FishersTheme.headline)
                                .foregroundStyle(Color.primary)
                            Text(template.blurb)
                                .font(FishersTheme.footnote)
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(minHeight: FishersTheme.minTap)
                }
            }
            Button {
                draft = PassDraft()
            } label: {
                Label(tr("Start from nothing"), systemImage: "square.and.pencil")
                    .frame(minHeight: FishersTheme.minTap)
            }
        } header: {
            Text(tr("Pick one to start from"))
        } footer: {
            Text(tr("You can change the name, price and what it covers next."))
        }
    }

    // MARK: Step 2

    @ViewBuilder
    private var form: some View {
        let binding = Binding(get: { draft ?? PassDraft() }, set: { draft = $0 })
        Section(tr("Name")) {
            TextField(tr("Winter nets pass"), text: binding.name)
                .textInputAutocapitalization(.words)
        }
        Section {
            HStack {
                Text(Money.format(0, currency).prefix { !$0.isNumber })
                    .foregroundStyle(.secondary)
                TextField(tr("Price"), text: binding.amount)
                    .keyboardType(.decimalPad)
            }
            .frame(minHeight: FishersTheme.minTap)
            Picker(tr("How it's paid"), selection: binding.billing) {
                Text(tr("Once")).tag(PassBilling.once)
                Text(tr("Every month")).tag(PassBilling.monthly)
                Text(tr("In parts")).tag(PassBilling.instalments)
            }
            .pickerStyle(.segmented)
            if binding.wrappedValue.billing == .instalments {
                Stepper(tr("In {n} monthly parts", vars: ["n": binding.wrappedValue.parts]), value: binding.parts, in: 2...12)
                    .frame(minHeight: FishersTheme.minTap)
            }
        } header: {
            Text(tr("Price"))
        } footer: {
            switch binding.wrappedValue.billing {
            case .monthly: Text(tr("Players pay by a standing order from their own bank. The app keeps track of each month."))
            case .instalments: Text(tr("The price is split into equal parts, one a month."))
            default: Text(tr("Paid once, like a session."))
            }
        }
        Section {
            ForEach(SessionKind.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: Binding(
                    get: { binding.wrappedValue.covers.contains(kind) },
                    set: { on in
                        if on { binding.wrappedValue.covers.insert(kind) } else { binding.wrappedValue.covers.remove(kind) }
                    }
                ))
                .frame(minHeight: FishersTheme.minTap)
            }
        } header: {
            Text(tr("What it covers"))
        } footer: {
            Text(tr("Leave them all off for a membership that doesn't cover sessions."))
        }
        Section {
            if binding.wrappedValue.billing == .monthly {
                Text(tr("Every month, until they cancel."))
            } else {
                Picker(tr("How long it lasts"), selection: binding.length) {
                    Text(tr("No end date")).tag(PassDraft.Length.noEnd)
                    Text(tr("Until a date")).tag(PassDraft.Length.until)
                    Text(tr("A number of sessions")).tag(PassDraft.Length.sessions)
                }
                switch binding.wrappedValue.length {
                case .until:
                    DatePicker(tr("Covers until"), selection: binding.validUntil, in: Date.now..., displayedComponents: .date)
                case .sessions:
                    Stepper(tr("{n} sessions", vars: ["n": binding.wrappedValue.sessions]), value: binding.sessions, in: 1...500)
                        .frame(minHeight: FishersTheme.minTap)
                case .noEnd:
                    EmptyView()
                }
            }
        } header: {
            Text(tr("How long it lasts"))
        }
        Section {
            Picker(tr("Who can have it"), selection: binding.priceTypeId) {
                Text(tr("Anyone")).tag(UUID?.none)
                ForEach(store.groups.inUse.filter { !$0.forGuests }) { group in
                    Text(tr("Only {group}", vars: ["group": group.name])).tag(UUID?.some(group.id))
                }
            }
            Toggle(tr("Players can get it themselves"), isOn: binding.openToJoin)
                .frame(minHeight: FishersTheme.minTap)
        } footer: {
            Text(binding.wrappedValue.openToJoin
                 ? tr("Players see it on the club's pay screen and can get it there.")
                 : tr("Only you and the club's other money admins can put people on it."))
        }
    }

    private func save() async {
        guard let draft else { return }
        if let local = draft.problem(currency: currency) {
            problem = local
            return
        }
        guard let body = draft.body(currency: currency) else { return }
        problem = nil
        if let failure = await store.create(body).failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}
