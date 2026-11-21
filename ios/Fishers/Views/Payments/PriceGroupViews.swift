import SwiftUI

/// Payments → Prices for juniors, students…: the groups that pay a different
/// price for a session (or nothing, or the guests' price).
struct PriceGroupsView: View {
    @StateObject private var store: PriceGroupsStore
    @State private var editing: EditedGroup?

    /// A group to change, or a new one (`group` nil) started from a name.
    struct EditedGroup: Identifiable {
        let id = UUID()
        let group: PriceType?
        var name = ""
        var free = false
        var forGuests = false
    }

    init(clubId: UUID) {
        _store = StateObject(wrappedValue: PriceGroupsStore(clubId: clubId))
    }

    var body: some View {
        List {
            if let notice = store.notice {
                Section { Label(notice, systemImage: "info.circle").font(FishersTheme.subhead) }
            }
            Section {
                if store.hasLoaded, store.groups.inUse.isEmpty {
                    Text(tr("No groups yet. Everybody pays the session's price."))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.groups.inUse) { group in
                    Button {
                        editing = EditedGroup(group: group, name: group.name, free: group.free, forGuests: group.forGuests)
                    } label: {
                        // Colours, not .primary/.secondary: in a button
                        // those are shades of the tint, pale green on white.
                        HStack {
                            Text(group.name).foregroundStyle(Color.primary)
                            Spacer()
                            Text(group.tags.joined(separator: " · "))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                        .frame(minHeight: FishersTheme.minTap)
                    }
                }
            } header: {
                Text(tr("Groups"))
            } footer: {
                Text(tr("A junior, a student or a guest can pay a different price for a session, and a coach can pay nothing. You set each session's prices when you add its cost."))
            }
            Section {
                ForEach(suggestions, id: \.name) { suggestion in
                    Button {
                        editing = suggestion
                    } label: {
                        Label(suggestion.name, systemImage: "plus")
                            .frame(minHeight: FishersTheme.minTap)
                    }
                }
                Button {
                    editing = EditedGroup(group: nil)
                } label: {
                    Label(tr("Another group"), systemImage: "plus")
                        .frame(minHeight: FishersTheme.minTap)
                }
            } header: {
                Text(tr("Add a group"))
            }
            Section {
                NavigationLink {
                    MemberPricesView(clubId: store.clubId)
                } label: {
                    Text(tr("Set each member's group"))
                        .frame(minHeight: FishersTheme.minTap)
                }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle(tr("Prices for juniors, students…"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(item: $editing) { edited in
            PriceGroupSheet(store: store, edited: edited)
        }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    /// The usual ones the club hasn't named yet.
    private var suggestions: [EditedGroup] {
        let have = Set(store.groups.inUse.map { $0.name.lowercased() })
        return [
            EditedGroup(group: nil, name: tr("Junior")),
            EditedGroup(group: nil, name: tr("Student")),
            EditedGroup(group: nil, name: tr("Coach"), free: true),
            EditedGroup(group: nil, name: tr("Guest"), forGuests: !store.groups.inUse.contains(where: \.forGuests)),
        ].filter { !have.contains($0.name.lowercased()) }
    }
}

/// Name a group, mark it free or the guests' price, or stop using it.
private struct PriceGroupSheet: View {
    @ObservedObject var store: PriceGroupsStore

    @Environment(\.dismiss) private var dismiss
    @State private var edited: PriceGroupsView.EditedGroup
    @State private var problem: String?
    @State private var confirmStop = false

    init(store: PriceGroupsStore, edited: PriceGroupsView.EditedGroup) {
        self.store = store
        _edited = State(initialValue: edited)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Name")) {
                    TextField(tr("Junior"), text: $edited.name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Toggle(tr("They pay nothing"), isOn: $edited.free)
                        .frame(minHeight: FishersTheme.minTap)
                } footer: {
                    Text(tr("For coaches, say. Their sessions show as free."))
                }
                Section {
                    Toggle(tr("This is the guests' price"), isOn: $edited.forGuests)
                        .frame(minHeight: FishersTheme.minTap)
                } footer: {
                    Text(tr("Guests on a bill (people who aren't in the club) pay this group's price. One group can be for guests."))
                }
                if edited.group != nil {
                    Section {
                        Button(tr("Stop using this group"), role: .destructive) { confirmStop = true }
                            .frame(minHeight: FishersTheme.minTap)
                    } footer: {
                        Text(tr("Members in it go back to the standard price."))
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .disabled(store.isWorking)
            .navigationTitle(edited.group == nil ? tr("Add a group") : edited.group?.name ?? "")
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
                            .disabled(edited.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog(tr("Stop using this group?"), isPresented: $confirmStop, titleVisibility: .visible) {
                Button(tr("Stop using it"), role: .destructive) { Task { await stop() } }
                Button(tr("Never mind"), role: .cancel) {}
            }
            .interactiveDismissDisabled(store.isWorking)
        }
    }

    private func save() async {
        problem = nil
        let outcome: PaymentWrite
        if let group = edited.group {
            outcome = await store.update(group, name: edited.name, free: edited.free, forGuests: edited.forGuests)
        } else {
            outcome = await store.create(name: edited.name, free: edited.free, forGuests: edited.forGuests)
        }
        if let failure = outcome.failure { problem = failure } else { dismiss() }
    }

    private func stop() async {
        guard let group = edited.group else { return }
        if let failure = await store.stopUsing(group).failure { problem = failure } else { dismiss() }
    }
}

// MARK: - Who pays for whom

/// Each member's price group and who pays for them, as the server has them,
/// and juniors added by name.
struct MemberPricesView: View {
    @StateObject private var store: PriceGroupsStore
    @State private var editing: MoneyMember?
    @State private var addingJunior = false
    @State private var search = ""

    init(clubId: UUID) {
        _store = StateObject(wrappedValue: PriceGroupsStore(clubId: clubId))
    }

    private var members: [MoneyMember] {
        store.members.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if let notice = store.notice {
                Section { Label(notice, systemImage: "info.circle").font(FishersTheme.subhead) }
            }
            Section {
                Button {
                    addingJunior = true
                } label: {
                    Label(tr("Add a junior by name"), systemImage: "figure.child")
                        .font(FishersTheme.headline)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap, alignment: .leading)
                }
            } footer: {
                Text(tr("For a junior with no phone or email of their own. Whoever pays for them sees what they owe."))
            }
            Section {
                ForEach(members) { member in
                    Button {
                        editing = member
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).foregroundStyle(Color.primary)
                            ForEach(store.lines(member), id: \.self) { line in
                                Text(line).font(FishersTheme.footnote).foregroundStyle(Color.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap, alignment: .leading)
                    }
                }
            } header: {
                Text(tr("Members"))
            } footer: {
                Text(tr("Tap somebody to set their price group, or who pays for them."))
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .searchable(text: $search)
        .navigationTitle(tr("Who pays for whom"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(item: $editing) { member in
            MemberMoneySheet(store: store, member: member)
        }
        .sheet(isPresented: $addingJunior) {
            AddJuniorSheet(store: store)
        }
        .alert(tr("Something went wrong"), isPresented: store.errorBinding) {
            Button(t("rest.ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

/// One member's price group and who pays for them, starting from what they
/// are now.
private struct MemberMoneySheet: View {
    @ObservedObject var store: PriceGroupsStore
    let member: MoneyMember

    @Environment(\.dismiss) private var dismiss
    /// Nil: the standard price.
    @State private var group: UUID?
    /// Nil: they pay for themselves.
    @State private var payer: UUID?
    @State private var problem: String?

    init(store: PriceGroupsStore, member: MoneyMember) {
        self.store = store
        self.member = member
        _group = State(initialValue: member.priceTypeId)
        _payer = State(initialValue: member.payerId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("Their price"), selection: $group) {
                        Text(tr("Standard price")).tag(UUID?.none)
                        ForEach(store.groups.inUse.filter { !$0.forGuests }) { group in
                            Text(group.name).tag(UUID?.some(group.id))
                        }
                    }
                    // The header names it: the label beside it as well
                    // squeezed "They pay for themselves" to "They p…mselves".
                    .labelsHidden()
                    .frame(minHeight: FishersTheme.minTap)
                } header: {
                    Text(tr("Their price"))
                } footer: {
                    Text(tr("Juniors and others can pay a different price for sessions."))
                }
                Section {
                    Picker(tr("Who pays for them"), selection: $payer) {
                        Text(tr("They pay for themselves")).tag(UUID?.none)
                        ForEach(store.payers.filter { $0.userId != member.userId }) { other in
                            Text(other.name).tag(UUID?.some(other.userId))
                        }
                    }
                    .labelsHidden()
                    .frame(minHeight: FishersTheme.minTap)
                } header: {
                    Text(tr("Who pays for them"))
                } footer: {
                    Text(tr("Whoever pays sees what they owe, and pays for everyone in one go."))
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .disabled(store.isWorking)
            .navigationTitle(member.name)
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
                            .disabled(group == member.priceTypeId && payer == member.payerId)
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
        }
    }

    /// Only what changed is sent.
    private func save() async {
        problem = nil
        if group != member.priceTypeId,
           let failure = await store.setGroup(member, to: group).failure {
            problem = failure
            return
        }
        if payer != member.payerId,
           let failure = await store.setPayer(member, to: payer).failure {
            problem = failure
            return
        }
        dismiss()
    }
}

/// A junior with no sign-in of their own: a name, who pays, their price.
private struct AddJuniorSheet: View {
    @ObservedObject var store: PriceGroupsStore

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var payer: UUID?
    @State private var group: UUID?
    @State private var problem: String?
    @State private var startedGroup = false

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Their name")) {
                    TextField(tr("Name"), text: $name)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
                }
                Section {
                    Picker(tr("Who pays for them"), selection: $payer) {
                        Text(tr("Pick somebody")).tag(UUID?.none)
                        ForEach(store.payers) { member in
                            Text(member.name).tag(UUID?.some(member.userId))
                        }
                    }
                    .labelsHidden()
                    .frame(minHeight: FishersTheme.minTap)
                } header: {
                    Text(tr("Who pays for them"))
                } footer: {
                    Text(tr("A parent, usually. They see what the junior owes and pay it."))
                }
                if !store.groups.inUse.isEmpty {
                    Section(tr("Their price")) {
                        Picker(tr("Their price"), selection: $group) {
                            Text(tr("Standard price")).tag(UUID?.none)
                            ForEach(store.groups.inUse.filter { !$0.forGuests }) { group in
                                Text(group.name).tag(UUID?.some(group.id))
                            }
                        }
                        .labelsHidden()
                        .frame(minHeight: FishersTheme.minTap)
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .disabled(store.isWorking)
            .navigationTitle(tr("Add a junior by name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isWorking {
                        ProgressView()
                    } else {
                        Button(tr("Add them")) { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || payer == nil)
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
            .onAppear {
                guard !startedGroup else { return }
                startedGroup = true
                group = store.groups.junior?.id
            }
        }
    }

    private func save() async {
        guard let payer else {
            problem = tr("Pick who pays for them.")
            return
        }
        problem = nil
        if let failure = await store.addJunior(name: name, payer: payer, group: group).failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}
