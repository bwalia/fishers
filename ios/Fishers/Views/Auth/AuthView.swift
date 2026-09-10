import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var mode: Mode = .login
    @State private var method: Method = .email
    @State private var name = ""
    /// One field for both: signing in, it is an address or a number; signing
    /// up, it is whichever `method` says.
    @State private var identifier = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    enum Mode { case login, signup }
    enum Field { case name, identifier, password }

    enum Method: String, CaseIterable, Identifiable {
        case email, phone
        var id: String { rawValue }
        var label: String { self == .email ? "Email" : "Mobile number" }
    }

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

                                Picker("Register with", selection: $method) {
                                    ForEach(Method.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                            if mode == .signup && method == .phone {
                                field("Mobile number", text: $identifier, field: .identifier)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
                            } else {
                                field(
                                    mode == .login ? "Email or mobile number" : "Email",
                                    text: $identifier,
                                    field: .identifier
                                )
                                .textContentType(mode == .login ? .username : .emailAddress)
                                .keyboardType(mode == .login ? .default : .emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            }
                            SecureField("Password", text: $password)
                                .font(FishersTheme.body)
                                .padding(.horizontal, 14)
                                .frame(minHeight: FishersTheme.minTap)
                                .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, FishersTheme.space2)

                    Spacer(minLength: FishersTheme.space4)
                }
            }
            .background(FishersTheme.mist.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(FishersTheme.accent)
    }

    private var trimmedIdentifier: String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        // The API asks for eight on signup; matching it here saves a round trip
        // that only ever comes back as an error.
        let passwordOk = mode == .signup ? password.count >= 8 : password.count >= 6
        guard !trimmedIdentifier.isEmpty, passwordOk else { return false }
        if mode == .signup {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func field(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .font(FishersTheme.body)
            .padding(.horizontal, 14)
            .frame(minHeight: FishersTheme.minTap)
            .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .focused($focused, equals: field)
    }

    private func submit() async {
        if mode == .login {
            await session.login(identifier: trimmedIdentifier, password: password)
        } else {
            // Send only the one they chose; the other stays absent rather than
            // an empty string the API would have to interpret.
            await session.signUp(
                name: name,
                email: method == .email ? trimmedIdentifier : nil,
                phone: method == .phone ? trimmedIdentifier : nil,
                password: password
            )
        }
    }
}
