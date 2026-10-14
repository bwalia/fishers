import AuthenticationServices
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
    /// Asked on the form, saved once the account exists.
    @State private var role: RoleIntent?
    @State private var googleConfig: SocialAuthConfig?
    @State private var appleEnabled = true
    @FocusState private var focused: Field?

    enum Mode { case login, signup }
    enum Field { case name, identifier, password }

    enum Method: String, CaseIterable, Identifiable {
        case email, phone
        var id: String { rawValue }
        var label: String { self == .email ? tr("Email") : tr("Mobile number") }

        /// Whether a value is plausibly the thing this method asks for.
        ///
        /// Deliberately loose. The API is the authority on what it will
        /// accept — this only catches the obvious mismatch, so it can never be
        /// the reason a real address or a foreign number is turned away. It
        /// exists because one field serves both methods: switching from
        /// Mobile number to Email used to leave the number behind, and the
        /// form sent it.
        func accepts(_ value: String) -> Bool {
            switch self {
            case .email:
                guard !value.contains(" "),
                      let at = value.firstIndex(of: "@"),
                      at != value.startIndex
                else { return false }
                let domain = value[value.index(after: at)...]
                return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
            case .phone:
                return value.filter(\.isNumber).count >= 7
                    && value.allSatisfy { $0.isNumber || "+-() ".contains($0) }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FishersTheme.space3) {
                    FishersBrandHeader(style: .hero, showsTagline: true)
                        .padding(.top, FishersTheme.space3)

                    VStack(alignment: .leading, spacing: FishersTheme.space2) {
                        Text(mode == .login ? tr("Welcome back") : tr("Join your club"))
                            .font(FishersTheme.title)
                            .tracking(-0.3)
                            .foregroundStyle(.primary)

                        Text(mode == .login
                             ? tr("Sign in to see fixtures, chats and selection.")
                             : tr("Create an account — you can be in a match within a minute."))
                            .font(FishersTheme.subhead)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if mode == .signup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(t("rest.im_here_to"))
                                    .font(FishersTheme.subhead.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                RoleChooserView(selection: $role, compact: true)
                            }
                        }

                        socialButtons

                        VStack(spacing: 12) {
                            if mode == .signup {
                                field("Name", text: $name, field: .name)
                                    .textContentType(.name)

                                Picker(tr("Register with"), selection: $method) {
                                    ForEach(Method.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                // One @State serves both methods, so switching
                                // left the old value behind: a mobile number
                                // sitting under a label saying Email, which the
                                // form then accepted and the API refused.
                                .onChange(of: method) { _, _ in identifier = "" }
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
                            if mode == .signup, !trimmedIdentifier.isEmpty, !identifierLooksRight {
                                Text(method == .email
                                     ? tr("That does not look like an email address.")
                                     : tr("That does not look like a mobile number."))
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            SecureField(t("cl.password"), text: $password)
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
                                    Text(mode == .login ? tr("Sign in") : tr("Create account"))
                                        .font(FishersTheme.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: FishersTheme.minTap)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(session.isLoading || !canSubmit)

                        Button(mode == .login ? tr("Need an account? Sign up") : tr("Have an account? Sign in")) {
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
            .task { await loadSocialConfig() }
        }
        .tint(FishersTheme.accent)
    }

    @ViewBuilder
    private var socialButtons: some View {
        let showGoogle = googleConfig.map(SocialAuth.googleAvailable) ?? false
        if appleEnabled || showGoogle {
            VStack(spacing: 10) {
                if appleEnabled {
                    SignInWithAppleButton(mode == .signup ? .signUp : .signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        focused = nil
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: FishersTheme.minTap)
                    .disabled(session.isLoading)
                }
                if showGoogle {
                    Button {
                        focused = nil
                        Task { await socialGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                                .font(.title3)
                            Text(mode == .signup ? tr("Sign up with Google") : tr("Continue with Google"))
                                .font(FishersTheme.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(session.isLoading)
                }
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                    Text(t("rest.or_with_email"))
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                }
                .padding(.top, 4)
            }
        }
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
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return identifierLooksRight
        }
        return true
    }

    /// Signing in this is not asked: the API is told an identifier and works
    /// out which it is, so a number and an address are both fine. Signing up
    /// the person has chosen one, and the other is a round trip that can only
    /// come back as a refusal.
    private var identifierLooksRight: Bool {
        mode == .login || method.accepts(trimmedIdentifier)
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
                password: password,
                role: role
            )
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.canceled.rawValue
            {
                return
            }
            session.errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  !token.isEmpty
            else {
                session.errorMessage = "Apple sign-in did not return a token — try again"
                return
            }
            var nameParts: [String] = []
            if let given = credential.fullName?.givenName, !given.isEmpty { nameParts.append(given) }
            if let family = credential.fullName?.familyName, !family.isEmpty { nameParts.append(family) }
            let social = SocialCredential(
                provider: .apple,
                identityToken: token,
                fullName: nameParts.isEmpty ? nil : nameParts.joined(separator: " "),
                email: credential.email
            )
            await session.signInSocial(social, role: mode == .signup ? role : nil)
        }
    }

    private func socialGoogle() async {
        do {
            guard let googleConfig else {
                session.errorMessage = "Google sign-in is not set up on this server"
                return
            }
            let credential = try await SocialAuth.signInWithGoogle(config: googleConfig)
            await session.signInSocial(credential, role: mode == .signup ? role : nil)
        } catch let error as SocialAuthError {
            if case .cancelled = error { return }
            session.errorMessage = error.localizedDescription
        } catch {
            let ns = error as NSError
            // GIDSignIn cancel code
            if ns.domain == "com.google.GIDSignIn", ns.code == -5 { return }
            session.errorMessage = error.localizedDescription
        }
    }

    private func loadSocialConfig() async {
        if let google = try? await FishersAPI.googleAuthConfig() {
            googleConfig = google
        }
        if let apple = try? await FishersAPI.appleAuthConfig() {
            appleEnabled = apple.enabled
        }
    }
}
