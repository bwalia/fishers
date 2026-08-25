import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    enum Mode { case login, signup }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [FishersTheme.pitch, FishersTheme.accent.opacity(0.85), Color.black.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Fishers")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Clubs, calendars, and match day — organised.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                VStack(spacing: 14) {
                    if mode == .signup {
                        field("Name", text: $name)
                    }
                    field("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                        .padding()
                        .background(.white.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        Task {
                            if mode == .login {
                                await session.login(email: email, password: password)
                            } else {
                                await session.signUp(name: name, email: email, password: password)
                            }
                        }
                    } label: {
                        Text(mode == .login ? "Sign in" : "Create account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundStyle(FishersTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(session.isLoading)

                    Button(mode == .login ? "Need an account? Sign up" : "Have an account? Sign in") {
                        mode = mode == .login ? .signup : .login
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .font(.subheadline)

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .padding()
            .background(.white.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
