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
            background

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 48)

                    FishersBrandHeader(
                        style: .hero,
                        showsTagline: true,
                        onDark: true
                    )
                    .padding(.horizontal, 28)

                    formCard
                        .padding(.horizontal, 22)

                    Spacer(minLength: 40)
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    FishersTheme.pitch,
                    FishersTheme.accent,
                    Color(red: 0.04, green: 0.16, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft pitch-line motif — atmosphere without clutter.
            GeometryReader { geo in
                Path { path in
                    let mid = geo.size.height * 0.42
                    path.move(to: CGPoint(x: 0, y: mid))
                    path.addQuadCurve(
                        to: CGPoint(x: geo.size.width, y: mid + 40),
                        control: CGPoint(x: geo.size.width * 0.5, y: mid - 50)
                    )
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 2)
            }
        }
        .ignoresSafeArea()
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .login ? "Welcome back" : "Join your club")
                .font(FishersTheme.title)
                .foregroundStyle(FishersTheme.ink)

            Text(mode == .login
                 ? "Sign in to see fixtures, chats and selection."
                 : "Create an account to organise nets, league and socials.")
                .font(FishersTheme.footnote)
                .foregroundStyle(FishersTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if mode == .signup {
                field("Name", text: $name)
            }
            field("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)

            SecureField("Password", text: $password)
                .font(FishersTheme.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(FishersTheme.mist)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .textContentType(mode == .login ? .password : .newPassword)

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
                    .font(FishersTheme.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(FishersTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(session.isLoading)
            .opacity(session.isLoading ? 0.7 : 1)

            Button(mode == .login ? "Need an account? Sign up" : "Have an account? Sign in") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = mode == .login ? .signup : .login
                }
            }
            .font(FishersTheme.subhead)
            .foregroundStyle(FishersTheme.accent)
            .frame(maxWidth: .infinity)

            if let error = session.errorMessage {
                Text(error)
                    .font(FishersTheme.footnote)
                    .foregroundStyle(FishersTheme.unavailable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(FishersTheme.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(FishersTheme.mist)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
