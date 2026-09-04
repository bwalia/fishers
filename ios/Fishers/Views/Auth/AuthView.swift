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
            ScrollView {
                VStack(spacing: FishersTheme.space3) {
                    FishersBrandHeader(style: .hero, showsTagline: true)
                        .padding(.top, FishersTheme.space3)

                    VStack(alignment: .leading, spacing: FishersTheme.space2) {
                        Text(mode == .login ? "Welcome back" : "Join your club")
                            .font(FishersTheme.title)
                            .tracking(-0.3)
                            .foregroundStyle(.primary)

                        Text(mode == .login
                             ? "Sign in to see fixtures, chats and selection."
                             : "Create an account, then tell us how you play.")
                            .font(FishersTheme.subhead)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 12) {
                            if mode == .signup {
                                field("Name", text: $name, field: .name)
                                    .textContentType(.name)
                            }
                            field("Email", text: $email, field: .email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Password", text: $password)
                                .font(FishersTheme.body)
                                .padding(.horizontal, 14)
                                .frame(minHeight: FishersTheme.minTap)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .textContentType(mode == .login ? .password : .newPassword)
                                .focused($focused, equals: .password)
                        }

                        Button {
                            focused = nil
                            Task { await submit() }
                        } label: {
                            Group {
                                if session.isLoading {
                                    ProgressView()
                                } else {
                                    Text(mode == .login ? "Sign in" : "Create account")
                                        .font(FishersTheme.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: FishersTheme.minTap)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(session.isLoading || !canSubmit)

                        Button(mode == .login ? "Need an account? Sign up" : "Have an account? Sign in") {
                            withAnimation(.snappy) {
                                mode = mode == .login ? .signup : .login
                            }
                        }
                        .font(FishersTheme.subhead.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: FishersTheme.minTap)

                        if let error = session.errorMessage {
                            Text(error)
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(FishersTheme.space2)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, FishersTheme.space2)

                    Spacer(minLength: FishersTheme.space4)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

    private func field(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .font(FishersTheme.body)
            .padding(.horizontal, 14)
            .frame(minHeight: FishersTheme.minTap)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .focused($focused, equals: field)
    }

    private func submit() async {
        if mode == .login {
            await session.login(email: email, password: password)
        } else {
            await session.signUp(name: name, email: email, password: password)
        }
    }
}
