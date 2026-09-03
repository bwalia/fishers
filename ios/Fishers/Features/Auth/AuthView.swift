import SwiftUI

struct AuthView: View {
    @Environment(AppState.self) private var app

    enum Mode: String, CaseIterable {
        case login = "Log In"
        case signup = "Sign Up"
    }

    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.cricket")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                        Text("Fishers")
                            .font(.largeTitle.bold())
                        Text("Organise your club. Show up. Play.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 12) {
                        if mode == .signup {
                            TextField("Full name", text: $name)
                                .textContentType(.name)
                        }
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(mode == .signup ? .newPassword : .password)
                    }
                    .textFieldStyle(.roundedBorder)

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    Button(action: submit) {
                        if isBusy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(mode.rawValue).frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isBusy || email.isEmpty || password.isEmpty)

                    Button("Try Demo Mode") {
                        app.setDemoMode(true)
                    }
                    .font(.subheadline)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() {
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if mode == .signup {
                    try await app.signup(name: name, email: email, password: password)
                } else {
                    try await app.login(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(AppState(demoMode: false))
}
