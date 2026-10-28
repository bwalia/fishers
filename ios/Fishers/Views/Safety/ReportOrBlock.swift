import SwiftUI

/// Reporting something, and blocking whoever posted it.
///
/// Attached with `.reportOrBlock(…)` wherever the app shows somebody else's
/// words or picture — a message, a listing, a profile. One modifier for both
/// because they are one decision in the person's head, and a long press is
/// where iOS puts actions that belong to the thing under your finger.
///
/// `person` is who posted it, and is nil where there is nobody to block: the
/// app's own notes, or a club rather than a member.
struct ReportOrBlockModifier: ViewModifier {
    /// Where the two actions hang off.
    enum Placement {
        /// A long press on a row — a message, a listing in a list.
        case longPress
        /// A menu in the navigation bar — a whole screen about one person.
        case toolbar
    }

    let placement: Placement
    let kind: ReportSubjectKind
    let subjectId: UUID
    let person: UUID?
    let personName: String?
    /// So the screen can drop what it is showing rather than leave a block
    /// that only takes effect next launch.
    let onBlocked: (UUID) -> Void

    @State private var reporting = false
    @State private var confirmingBlock = false
    @State private var busy = false
    @State private var note = ""
    @State private var reason: ReportReason = .abuse
    @State private var outcome: String?

    func body(content: Content) -> some View {
        placed(content)
            .sheet(isPresented: $reporting) {
                reportSheet
            }
            .confirmationDialog(
                personName.map { t("mod.block_name", vars: ["name": $0]) } ?? t("mod.block"),
                isPresented: $confirmingBlock,
                titleVisibility: .visible
            ) {
                Button(t("mod.block"), role: .destructive) { send(.block) }
                Button(t("sc.cancel"), role: .cancel) {}
            } message: {
                Text(t("mod.block_explains"))
            }
            .alert(outcome ?? "", isPresented: .constant(outcome != nil)) {
                Button(t("rest.ok")) { outcome = nil }
            }
    }

    /// A long press belongs on a row — the thing under your finger. A whole
    /// screen has no "under your finger", so a profile gets a toolbar menu
    /// instead, which is where iOS keeps actions about what you are looking at.
    @ViewBuilder
    private func placed(_ content: Content) -> some View {
        switch placement {
        case .longPress:
            content.contextMenu { actions }
        case .toolbar:
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        actions
                    } label: {
                        Label(t("mod.safety"), systemImage: "ellipsis.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            reporting = true
        } label: {
            Label(t("mod.report"), systemImage: "flag")
        }
        if person != nil {
            Button(role: .destructive) {
                confirmingBlock = true
            } label: {
                Label(t("mod.block"), systemImage: "hand.raised")
            }
        }
    }

    private var reportSheet: some View {
        NavigationStack {
            Form {
                Section(t("mod.what_is_wrong")) {
                    // A plain list of rows rather than a Picker: six reasons
                    // read as six choices, and a wheel hides five of them.
                    ForEach(ReportReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(.primary)
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(FishersTheme.accent)
                                }
                            }
                        }
                        .accessibilityAddTraits(reason == option ? [.isSelected] : [])
                    }
                }
                Section(t("mod.anything_else")) {
                    TextField(t("mod.anything_else"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(t("mod.report_this"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { reporting = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("mod.send_report")) { send(.report) }
                        .disabled(busy)
                }
            }
        }
    }

    private enum Action { case report, block }

    private func send(_ action: Action) {
        busy = true
        Task {
            do {
                switch action {
                case .report:
                    try await FishersAPI.report(kind, id: subjectId, reason: reason, note: note)
                    reporting = false
                    outcome = t("mod.report_sent")
                case .block:
                    guard let person else { return }
                    try await FishersAPI.block(userId: person)
                    onBlocked(person)
                }
            } catch {
                outcome = action == .report
                    ? t("mod.report_would_not_send")
                    : t("mod.block_would_not_save")
            }
            busy = false
        }
    }
}

extension View {
    func reportOrBlock(
        _ kind: ReportSubjectKind,
        id subjectId: UUID,
        person: UUID?,
        personName: String? = nil,
        placement: ReportOrBlockModifier.Placement = .longPress,
        onBlocked: @escaping (UUID) -> Void = { _ in }
    ) -> some View {
        modifier(
            ReportOrBlockModifier(
                placement: placement,
                kind: kind,
                subjectId: subjectId,
                person: person,
                personName: personName,
                onBlocked: onBlocked
            )
        )
    }
}
