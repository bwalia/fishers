import SwiftUI
import UniformTypeIdentifiers

/// Payments → Import a bank statement, for money admins: choose the CSV the
/// bank exports, see what it matches in three groups — ticked off, needs a
/// look, not recognised — and apply what's ticked in one go.
///
/// Nothing is ticked off until Apply. The statement is held in memory only,
/// and only until it's applied or the sheet closes.
struct StatementImportSheet: View {
    @StateObject private var store: StatementImportStore

    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var showUnknown = false

    /// `waiting` is the payments still to check, for "Said £6, sent £9".
    init(clubId: UUID, waiting: [ClubPayment]) {
        _store = StateObject(wrappedValue: StatementImportStore(clubId: clubId, waiting: waiting))
    }

    var body: some View {
        NavigationStack {
            List {
                if let applied = store.applied {
                    doneSections(applied)
                } else if let preview = store.preview {
                    previewSections(preview)
                } else {
                    startSections
                }
            }
            .listStyle(.insetGrouped)
            .fishersList()
            .navigationTitle(tr("Import a bank statement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.applied == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("sc.cancel")) { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                guard case .success(let url) = result else { return }
                Task { await store.read(url) }
            }
        }
    }

    // MARK: Choosing the file

    @ViewBuilder
    private var startSections: some View {
        Section {
            Text(tr("Download a statement from your bank's website as a CSV file, then choose it here. Payments with a member's reference are ticked off for you. The statement isn't kept."))
                .font(FishersTheme.subhead)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
        if store.isWorking {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(tr("Reading the statement…")).font(FishersTheme.subhead)
                }
                .frame(minHeight: FishersTheme.minTap)
            }
        } else if let problem = store.problem {
            Section {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(FishersTheme.subhead)
                    .foregroundStyle(FishersTheme.unavailable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Section {
            bigButton(store.problem == nil ? tr("Choose the CSV file") : tr("Choose another file")) { choosing = true }
        }
    }

    // MARK: What it matched

    @ViewBuilder
    private func previewSections(_ preview: StatementPreview) -> some View {
        Section {
            if preview.toApply.isEmpty {
                Text(tr("Nothing to tick off."))
                    .foregroundStyle(.secondary)
            }
            ForEach(preview.toApply) { line in
                Toggle(isOn: Binding(get: { store.ticked.contains(line.hash) }, set: { store.toggle(line, $0) })) {
                    StatementLineRow(line: line, currency: preview.currency, detail: line.applyWords)
                }
                .frame(minHeight: FishersTheme.minTap)
            }
        } header: {
            Text(tr("Ticked off: {n}", vars: ["n": preview.toApply.count]))
        } footer: {
            if !preview.toApply.isEmpty {
                Text(tr("These match a member. Untick any you'd rather check by hand."))
            }
        }

        if !preview.toCheck.isEmpty {
            Section {
                ForEach(preview.toCheck) { line in
                    StatementLineRow(
                        line: line, currency: preview.currency,
                        detail: line.whyWords(currency: preview.currency, memberNames: store.memberNames, waiting: store.waiting),
                        detailColour: FishersTheme.maybe, showsBankText: true
                    )
                }
            } header: {
                Text(tr("Needs a look: {n}", vars: ["n": preview.toCheck.count]))
            } footer: {
                Text(tr("These aren't ticked off for you. Tick them by hand under Payments to check, or record them under Who owes what."))
            }
        }

        if !preview.notRecognised.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showUnknown) {
                    ForEach(preview.notRecognised) { line in
                        StatementLineRow(line: line, currency: preview.currency)
                    }
                } label: {
                    Text(tr("Not recognised: {n}", vars: ["n": preview.notRecognised.count]))
                        .font(FishersTheme.subhead.weight(.semibold))
                        .frame(minHeight: FishersTheme.minTap)
                }
            } footer: {
                Text(tr("Nobody's reference is in these: other money into the account, or a payment made without a reference."))
            }
        }

        if !preview.alreadyDone.isEmpty {
            Section {
                Label(tr("Already done: {n}", vars: ["n": preview.alreadyDone.count]), systemImage: "checkmark.circle")
                    .font(FishersTheme.subhead)
                    .foregroundStyle(.secondary)
            }
        }

        if let problem = store.problem {
            Section {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(FishersTheme.subhead)
                    .foregroundStyle(FishersTheme.unavailable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Section {
            bigButton(tr("Apply {n}", vars: ["n": store.tickedCount])) {
                Task { await store.apply() }
            }
            .disabled(store.tickedCount == 0)
        }
    }

    // MARK: Done

    @ViewBuilder
    private func doneSections(_ applied: StatementApplied) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(applied.headline, systemImage: "checkmark.seal.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(FishersTheme.available)
                    .fixedSize(horizontal: false, vertical: true)
                if let skipped = applied.skippedWords {
                    Text(skipped)
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(tr("Each person is told their payment arrived."))
                    .font(FishersTheme.subhead)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        Section {
            bigButton(tr("Done")) { dismiss() }
        }
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if store.isWorking {
                    ProgressView()
                } else {
                    Text(title).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(FishersTheme.pitch)
        .disabled(store.isWorking)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

/// One payment into the account: who, why if it needs saying, how much and
/// when. The bank's own words underneath where a person has to compare.
private struct StatementLineRow: View {
    let line: StatementLine
    let currency: String
    var detail: String?
    var detailColour: Color = .secondary
    /// The bank's words under a name, so the treasurer can find it there.
    var showsBankText = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.who)
                    .font(FishersTheme.subhead.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(detailColour)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsBankText, line.name != nil {
                    Text(line.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(line.amountCents, currency))
                    .font(FishersTheme.subhead.monospacedDigit())
                Text(line.day)
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
