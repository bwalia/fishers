import SwiftUI
import UIKit

/// The first time a money admin opens Payments with nothing set up: where
/// players send money (with a preview of what they will see), what the club
/// usually charges, then what happens after each session. Either of the
/// first two can be skipped and done later from the Payments screen.
struct PaymentSetupWizard: View {
    @ObservedObject var store: ClubMoneyStore

    enum Step { case bank, prices, done }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var draft = BankDetailsDraft()
    @State private var prices: UsualPricesDraft
    @State private var problem: String?
    @State private var passwordProblem: String?
    @FocusState private var passwordFocused: Bool

    init(store: ClubMoneyStore) {
        self.store = store
        let overview = store.overview
        // Bank details added some other way since: carry on from the prices.
        _step = State(initialValue: (overview?.account.isEmpty ?? true) ? .bank : .prices)
        _prices = State(initialValue: UsualPricesDraft(
            overview?.settings.usualPrices ?? UsualPrices(), currency: overview?.currency ?? Money.fallbackCurrency
        ))
    }

    private var currency: String { store.overview?.currency ?? Money.fallbackCurrency }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .bank: bankStep
                case .prices: pricesStep
                case .done: doneStep
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(tr("Set up payments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("sc.cancel")) { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
            .disabled(store.isWorking)
        }
    }

    // MARK: 1. Where players send money

    @ViewBuilder
    private var bankStep: some View {
        stepHeading(1, tr("Where players send money"),
                    tr("The bank account players pay into. You can change it later."))
        BankDetailsFields(draft: $draft, passwordProblem: passwordProblem, passwordFocused: $passwordFocused)
        PayeePreview(draft: draft)
        nextButtons(save: tr("Save and carry on")) { await saveBank() }
    }

    private func saveBank() async {
        passwordProblem = nil
        if let local = draft.problem {
            problem = local
            return
        }
        problem = nil
        switch await store.saveBankDetails(draft.body) {
        case .saved:
            step = .prices
        case .needsPassword(let message):
            passwordProblem = message
            draft.password = ""
            passwordFocused = true
        case .refused(let message):
            problem = message
        }
    }

    // MARK: 2. What you usually charge

    @ViewBuilder
    private var pricesStep: some View {
        stepHeading(2, tr("What you usually charge"),
                    tr("Each new nets session or match starts from these. You can change the price each time."))
        UsualPricesFields(draft: $prices, currency: currency)
        nextButtons(save: tr("Save and carry on")) { await savePrices() }
    }

    private func savePrices() async {
        guard let chosen = prices.prices(currency: currency) else {
            problem = tr("Put in an amount, or switch that price off.")
            return
        }
        problem = nil
        if let failure = await store.saveUsualPrices(chosen).failure {
            problem = failure
        } else {
            step = .done
        }
    }

    // MARK: 3. Done

    @ViewBuilder
    private var doneStep: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label(tr("You're set up"), systemImage: "checkmark.seal.fill")
                    .font(FishersTheme.title)
                    .foregroundStyle(FishersTheme.available)
                Text(tr("After each session, tick who came and send the bill. Then share it to WhatsApp: players tap the link and pay, with no app and no password."))
                    .font(FishersTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        Section {
            Button {
                dismiss()
            } label: {
                Text(tr("Done"))
                    .font(FishersTheme.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.borderedProminent)
            .tint(FishersTheme.pitch)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: Pieces

    private func stepHeading(_ number: Int, _ title: String, _ detail: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Step {n} of 3", vars: ["n": number]))
                    .font(FishersTheme.overline)
                    .foregroundStyle(FishersTheme.pitch)
                Text(title).font(FishersTheme.title)
                Text(detail)
                    .font(FishersTheme.subhead)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func nextButtons(save: String, action: @escaping () async -> Void) -> some View {
        Section {
            VStack(spacing: 10) {
                Button {
                    Task { await action() }
                } label: {
                    Group {
                        if store.isWorking { ProgressView() } else { Text(save).lineLimit(1) }
                    }
                    .font(FishersTheme.headline)
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.borderedProminent)
                .tint(FishersTheme.pitch)
                Button {
                    problem = nil
                    step = step == .bank ? .prices : .done
                } label: {
                    Text(tr("Skip for now"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.bordered)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }
}

/// The pay screen's top, as players will see it, from what is being typed.
struct PayeePreview: View {
    let draft: BankDetailsDraft

    private var holder: String {
        let typed = draft.holder.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? tr("Account name") : typed
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(Payee.sentence(holder, role: nil))
                    .font(FishersTheme.headline)
                if let own = Payee.ownAccountSentence(holder, isPersonal: draft.isPersonal) {
                    Text(own)
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            LabeledContent(tr("Name"), value: holder)
            LabeledContent(tr("Sort code"), value: draft.sortCode.isEmpty ? "–" : draft.sortCode)
            LabeledContent(tr("Account number"), value: BankDetailsCheck.digits(draft.account).isEmpty ? "–" : BankDetailsCheck.digits(draft.account))
                .privacySensitive()
            LabeledContent(tr("What to write in the reference box"), value: tr("Their surname, like SHARMA"))
        } header: {
            Text(tr("What players will see"))
        } footer: {
            Text(tr("Each line has a Copy button, so players can paste it into their banking app."))
        }
    }
}

/// The usual nets price and match fee, each switched on or off.
struct UsualPricesFields: View {
    @Binding var draft: UsualPricesDraft
    let currency: String

    var body: some View {
        Section {
            Toggle(tr("Nets have a usual price"), isOn: $draft.netsOn)
                .frame(minHeight: FishersTheme.minTap)
        } header: {
            Text(tr("Nets"))
        }
        if draft.netsOn {
            CostFields(mode: $draft.netsMode, amount: $draft.netsAmount, currency: currency)
        }
        Section {
            Toggle(tr("Matches have a usual fee"), isOn: $draft.matchOn)
                .frame(minHeight: FishersTheme.minTap)
            if draft.matchOn {
                HStack {
                    Text(Money.format(0, currency).prefix { !$0.isNumber })
                        .foregroundStyle(.secondary)
                    TextField(tr("Each person pays"), text: $draft.matchAmount)
                        .keyboardType(.decimalPad)
                }
                .frame(minHeight: FishersTheme.minTap)
            }
        } header: {
            Text(tr("Matches"))
        } footer: {
            Text(tr("A match fee is the same for everyone who plays."))
        }
    }
}

/// Change the usual prices, from the Payments screen.
struct UsualPricesSheet: View {
    @ObservedObject var store: ClubMoneyStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft: UsualPricesDraft
    @State private var problem: String?

    init(store: ClubMoneyStore) {
        self.store = store
        _draft = State(initialValue: UsualPricesDraft(
            store.overview?.settings.usualPrices ?? UsualPrices(),
            currency: store.overview?.currency ?? Money.fallbackCurrency
        ))
    }

    private var currency: String { store.overview?.currency ?? Money.fallbackCurrency }

    var body: some View {
        NavigationStack {
            Form {
                UsualPricesFields(draft: $draft, currency: currency)
                if let problem {
                    Section { Text(problem).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .navigationTitle(tr("Usual prices"))
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
                    }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
        }
    }

    private func save() async {
        guard let chosen = draft.prices(currency: currency) else {
            problem = tr("Put in an amount, or switch that price off.")
            return
        }
        problem = nil
        if let failure = await store.saveUsualPrices(chosen).failure {
            problem = failure
        } else {
            dismiss()
        }
    }
}

/// The picture a payer attached to say they paid. Only money admins can
/// open it; it is fetched when opened and kept nowhere.
struct PaymentScreenshotSheet: View {
    @ObservedObject var store: ClubMoneyStore
    let payment: ClubPayment

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: "\(payment.name) · \(Money.format(payment.amountCents, payment.currency))")
                        .font(FishersTheme.headline)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(tr("Screenshot of the payment"))
                    } else if let problem {
                        Text(problem).foregroundStyle(FishersTheme.unavailable)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            .navigationTitle(tr("Screenshot"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
            .task {
                do {
                    image = try await store.screenshot(of: payment)
                } catch {
                    problem = paymentMessage(error)
                }
            }
        }
    }
}
