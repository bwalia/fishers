import SwiftUI

/// Sign in with a mobile number and the six-digit code WhatsApp brings — no
/// password to remember. Only offered while the server has it switched on.
struct WhatsAppSignInSheet: View {
    @ObservedObject var store: WhatsAppSignInStore
    let onSignedIn: (AuthTokens) async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                switch store.step {
                case .number: numberStep
                case .code: codeStep
                }
                if let problem = store.problem {
                    Section {
                        Text(problem)
                            .foregroundStyle(FishersTheme.unavailable)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(tr("Sign in with WhatsApp"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
            }
            .interactiveDismissDisabled(store.isWorking)
            .onAppear { focused = true }
            .onChange(of: store.isEnabled) { _, on in
                // Switched off while the sheet was open: the sentence says so,
                // and there is nothing more to do here.
                if !on { focused = false }
            }
        }
    }

    // MARK: Your number

    @ViewBuilder
    private var numberStep: some View {
        Section {
            TextField(tr("Mobile number"), text: $store.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .font(.title3)
                .frame(minHeight: FishersTheme.minTap)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { Task { await store.sendCode() } }
        } header: {
            Text(tr("Your mobile number"))
        } footer: {
            Text(tr("The one on your account, with the country code first, like +44 7700 900123. We send a code to it on WhatsApp."))
        }
        Section {
            bigButton(tr("Send me a code"), enabled: store.canSendCode && store.isEnabled) {
                await store.sendCode()
            }
        }
    }

    // MARK: The code

    @ViewBuilder
    private var codeStep: some View {
        Section {
            TextField(tr("6-digit code"), text: Binding(get: { store.code }, set: { store.setCode($0) }))
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.title.monospacedDigit())
                .frame(minHeight: FishersTheme.minTap)
                .focused($focused)
                .onChange(of: store.code) { _, code in
                    if code.count == WhatsAppSignInStore.codeLength { Task { await verify() } }
                }
        } header: {
            Text(tr("Type the code from WhatsApp"))
        } footer: {
            Text(tr("We sent it to {number} on WhatsApp.", vars: ["number": store.phone]))
        }
        Section {
            bigButton(tr("Sign in"), enabled: store.canVerify) { await verify() }
        }
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button(tr("Send a new code")) { Task { await store.sendCode() } }
                    .disabled(!store.canResend(at: context.date) || store.isWorking)
                    .frame(minHeight: FishersTheme.minTap)
            }
            Button(tr("Use a different number")) {
                store.useAnotherNumber()
                focused = true
            }
            .frame(minHeight: FishersTheme.minTap)
        }
    }

    private func bigButton(_ title: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Group {
                if store.isWorking { ProgressView() } else { Text(title).lineLimit(1) }
            }
            .font(FishersTheme.headline)
            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func verify() async {
        guard let tokens = await store.verify() else { return }
        await onSignedIn(tokens)
        dismiss()
    }
}
