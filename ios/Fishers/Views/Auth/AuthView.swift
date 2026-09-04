import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    enum Mode { case login, signup }
    enum Field { case name, email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FishersBrandHeader(style: .hero, showsTagline: true)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: FishersTheme.space3, leading: 0, bottom: FishersTheme.space2, trailing: 0))
                }

                Section {
                    if mode == .signup {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                            .focused($focused, equals: .name)
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                    SecureField("Password", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                        .focused($focused, equals: .password)
                } header: {
                    Text(mode == .login ? "Sign in" : "Create account")
                } footer: {
                    Text(mode == .login
                         ? "Use your club email to see fixtures, chats and selection."
                         : "You’ll set up how you play after creating an account.")
                }

                Section {
                    Button {
                        focused = nil
                        Task { await submit() }
                    } label: {
                        if session.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(mode == .login ? "Sign in" : "Create account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isLoading || !canSubmit)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    Button(mode == .login ? "Need an account? Sign up" : "Have an account? Sign in") {
                        withAnimation(.snappy) {
                            mode = mode == .login ? .signup : .login
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                if let error = session.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(error)")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(FishersTheme.accent)
    }

    private var canSubmit: Bool {
        let emailOk = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let passwordOk = password.count >= 6
        if mode == .signup {
            return emailOk && passwordOk && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return emailOk && passwordOk
    }

    private func submit() async {
        if mode == .login {
            await session.login(email: email, password: password)
        } else {
            await session.signUp(name: name, email: email, password: password)
        }
    }
}
