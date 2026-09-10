import SwiftUI

/// The club secretary's screen: who is in the club, who runs it, what the
/// assistant is allowed to do, and who still owes money.
///
/// Everything here was API-only before, which meant appointing a captain took a
/// curl command.
struct ClubAdminView: View {
    let club: Club
    let role: ClubRoleInfo?

    @StateObject private var store: ClubAdminStore
    @State private var tab: Tab = .roster

    enum Tab: String, CaseIterable, Identifiable {
        case roster = "Members"
        case settings = "Policy"
        case fees = "Fees"
        var id: String { rawValue }
    }

    init(club: Club, role: ClubRoleInfo?) {
        self.club = club
        self.role = role
        _store = StateObject(wrappedValue: ClubAdminStore(clubId: club.id))
    }

    private var isSecretary: Bool { role?.isSecretary ?? false }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch tab {
            case .roster: RosterList(store: store, canManage: isSecretary)
            case .settings: PolicyForm(store: store, canManage: isSecretary)
            case .fees: FeesList(store: store, canChase: role?.isCaptain ?? false)
            }
        }
        .navigationTitle("Manage club")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .alert("Something went wrong", isPresented: store.errorBinding) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

// MARK: - Roster

private struct RosterList: View {
    @ObservedObject var store: ClubAdminStore
    let canManage: Bool

    @State private var isAdding = false
    @State private var newIdentifier = ""
    @State private var newRole: ClubRole = .member
    @State private var editing: ClubMemberDetail?

    var body: some View {
        List {
            if !canManage {
                Section {
                    Label(
                        "Only a club secretary can change roles or the roster.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(ClubRole.rosterOrder, id: \.self) { role in
                let members = store.members.filter { $0.role == role && $0.isActive }
                if !members.isEmpty {
                    Section(role.displayName + (members.count > 1 ? "s" : "")) {
                        ForEach(members) { member in
                            row(member)
                        }
                    }
                }
            }

            let former = store.members.filter { !$0.isActive }
            if !former.isEmpty {
                Section("No longer in the club") {
                    ForEach(former) { member in
                        Text(member.name).foregroundStyle(.secondary)
                    }
                }
            }

            if store.members.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "No members yet",
                    systemImage: "person.3",
                    description: Text("Add players by the email they signed up with.")
                )
            }
        }
        .listStyle(.insetGrouped)
            .fishersList()
        .toolbar {
            if canManage {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Add a member")
                }
            }
        }
        .sheet(isPresented: $isAdding) { addSheet }
        .sheet(item: $editing) { member in
            RoleSheet(member: member) { role in
                Task { await store.setRole(member: member, role: role) }
            } onRemove: {
                Task { await store.remove(member: member) }
            }
        }
    }

    /// Two targets, because there are two things to do with a name.
    ///
    /// Tapping the person opens their record — everyone can do that. The role
    /// badge is the button that changes it, and only a secretary sees it as a
    /// button. The row used to do nothing at all for anybody who could not
    /// manage the club, which is most of the club.
    private func row(_ member: ClubMemberDetail) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                PlayerProfileView(userId: member.userId, knownName: member.name)
            } label: {
                HStack(spacing: 10) {
                    AvatarView(name: member.name, urlString: member.avatarUrl, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name).font(.subheadline.weight(.medium))
                        if !member.subtitle.isEmpty {
                            Text(member.subtitle).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(member.contact).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityLabel("\(member.name), \(member.role.displayName). Open their profile.")

            if canManage {
                Button {
                    editing = member
                } label: {
                    RoleBadge(role: member.role)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change \(member.name)'s role")
            } else {
                RoleBadge(role: member.role)
            }
        }
        .frame(minHeight: FishersTheme.minTap)
    }

    private var trimmedIdentifier: String {
        newIdentifier.trimmingCharacters(in: .whitespaces)
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email or mobile number", text: $newIdentifier)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Whatever they signed up with. Somebody who registered with a mobile number has no address to look up.")
                }
                Section("Role") {
                    Picker("Role", selection: $newRole) {
                        ForEach(ClubRole.appointable, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button {
                        Task { await store.makeInvite(email: trimmedIdentifier) }
                    } label: {
                        Label("Make an invite link instead", systemImage: "link")
                    }
                    if let invite = store.invite,
                       let url = invite.url(webBase: AppConfig.webBaseURL.absoluteString) {
                        ShareLink(item: url) {
                            Label(url.absoluteString, systemImage: "square.and.arrow.up")
                                .font(.footnote)
                                .lineLimit(2)
                        }
                    }
                } footer: {
                    Text("An invite link works for somebody with no Fishers account. It joins them to the club once they sign up, and can only be used once.")
                }
            }
            .navigationTitle("Add a member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isAdding = false
                        store.invite = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let identifier = trimmedIdentifier
                        let role = newRole
                        isAdding = false
                        newIdentifier = ""
                        newRole = .member
                        store.invite = nil
                        Task { await store.add(identifier: identifier, role: role) }
                    }
                    .bold()
                    .disabled(trimmedIdentifier.isEmpty)
                }
            }
        }
    }
}

private struct RoleBadge: View {
    let role: ClubRole

    var body: some View {
        Text(role.shortLabel)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colour.opacity(0.16), in: Capsule())
            .foregroundStyle(colour)
    }

    private var colour: Color {
        switch role {
        case .clubAdmin, .superAdmin: return FishersTheme.accent
        case .teamCaptain: return FishersTheme.pitch
        case .teamViceCaptain: return FishersTheme.maybe
        case .member, .guest: return .secondary
        }
    }
}

/// Appointing a captain is the single most consequential thing a secretary
/// does, so it gets a screen that says what each role can do.
private struct RoleSheet: View {
    let member: ClubMemberDetail
    var onSet: (ClubRole) -> Void
    var onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var role: ClubRole
    @State private var confirmRemove = false

    init(
        member: ClubMemberDetail,
        onSet: @escaping (ClubRole) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.member = member
        self.onSet = onSet
        self.onRemove = onRemove
        _role = State(initialValue: member.role)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ClubRole.appointable, id: \.self) { option in
                        Button {
                            role = option
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: role == option
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(FishersTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName).font(.subheadline.weight(.semibold))
                                    Text(option.responsibilities)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(member.name)
                } footer: {
                    Text("A club must always keep at least one secretary.")
                }

                Section {
                    Button("Remove from the club", role: .destructive) {
                        confirmRemove = true
                    }
                }
            }
            .navigationTitle("Role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSet(role)
                        dismiss()
                    }
                    .bold()
                    .disabled(role == member.role)
                }
            }
            .confirmationDialog(
                "Remove \(member.name) from the club?",
                isPresented: $confirmRemove,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    onRemove()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their past availability, fees and appearances stay on record.")
            }
        }
    }
}

// MARK: - Policy

private struct PolicyForm: View {
    @ObservedObject var store: ClubAdminStore
    let canManage: Bool

    var body: some View {
        Form {
            if let settings = store.settings {
                Section {
                    Picker("The assistant", selection: autonomy) {
                        ForEach(SelectionAutonomy.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(autonomy.wrappedValue.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Squad selection")
                }

                Section {
                    Stepper(
                        "Ask to reconfirm: \(settings.confirmLeadHours)h before",
                        value: binding(\.confirmLeadHours), in: 0...168, step: 6
                    )
                    Stepper(
                        "Drop the unconfirmed: \(settings.dropLeadHours)h before",
                        value: binding(\.dropLeadHours), in: 0...168, step: 6
                    )
                } header: {
                    Text("Chasing the squad")
                } footer: {
                    Text("Selected players are asked to reconfirm, then their place goes to a reserve.")
                }

                Section {
                    Stepper(
                        "First reminder: \(settings.feeChaseAfterHours)h after the game",
                        value: binding(\.feeChaseAfterHours), in: 0...336, step: 6
                    )
                    Stepper(
                        "At most \(settings.feeChaseMaxReminders) reminder\(settings.feeChaseMaxReminders == 1 ? "" : "s")",
                        value: binding(\.feeChaseMaxReminders), in: 0...10
                    )
                } header: {
                    Text("Match fees")
                } footer: {
                    Text("Then daily until they pay or the cap is reached.")
                }

                if store.isSaving {
                    Section { HStack { ProgressView(); Text("Saving…") } }
                }
            } else if store.isLoading {
                Section { ProgressView() }
            }
        }
        .disabled(!canManage || store.isSaving)
    }

    private var autonomy: Binding<SelectionAutonomy> {
        Binding(
            get: {
                SelectionAutonomy(rawValue: store.settings?.selectionAutonomy ?? "suggest") ?? .suggest
            },
            set: { new in
                store.mutateSettings { $0.selectionAutonomy = new.rawValue }
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<ClubSettings, Int>) -> Binding<Int> {
        Binding(
            get: { store.settings?[keyPath: keyPath] ?? 0 },
            set: { new in store.mutateSettings { $0[keyPath: keyPath] = new } }
        )
    }
}

// MARK: - Fees

private struct FeesList: View {
    @ObservedObject var store: ClubAdminStore
    let canChase: Bool

    var body: some View {
        List {
            if let fees = store.fees {
                Section {
                    LabeledContent("Outstanding") {
                        Text(String(format: "£%.2f", Double(fees.totalCents) / 100))
                            .font(.headline.monospacedDigit())
                    }
                    LabeledContent("People", value: "\(fees.count)")
                }
                if fees.owed.isEmpty {
                    Section {
                        Label("Everyone has paid.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(FishersTheme.available)
                    }
                } else {
                    Section("Who owes") {
                        ForEach(fees.owed) { fee in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(fee.name).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(String(format: "£%.2f", Double(fee.amountCents ?? 0) / 100))
                                        .font(.subheadline.monospacedDigit())
                                }
                                Text("\(fee.fixture) · \(fee.startAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if fee.remindersSent > 0 {
                                    Text("\(fee.remindersSent) reminder\(fee.remindersSent == 1 ? "" : "s") sent")
                                        .font(.caption2)
                                        .foregroundStyle(FishersTheme.maybe)
                                }
                            }
                        }
                    }
                    if canChase {
                        Section {
                            Button {
                                Task { await store.chaseFees() }
                            } label: {
                                if store.isChasing {
                                    HStack { ProgressView(); Text("Sending…") }
                                } else {
                                    Label("Send reminders now", systemImage: "envelope.badge")
                                }
                            }
                            .disabled(store.isChasing)
                        } footer: {
                            Text("The scheduler does this on its own; this is the do-it-now button.")
                        }
                    }
                }
            } else if store.isLoading {
                ProgressView()
            }
        }
        .listStyle(.insetGrouped)
    }
}
