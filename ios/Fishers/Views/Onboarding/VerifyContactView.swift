import SwiftUI

/// Confirm an email address or a mobile number with a six-digit code.
///
/// The field is there from the start rather than behind a "send code" button:
/// signing up already sent the first code, so most people only need to type
/// it. "Send a new code" covers the rest, and counts down when the server says
/// it is too soon to ask again.
struct VerifyContactView: View {
    let status: VerificationStatus
    /// Inside another card (a gated form): no heading of its own.
    var compact = false
    let onVerified: (PublicUser) -> Void

    @State private var channel: VerificationChannel = .email
    @State private var code = ""
    @State private var busy = false
    @State private var note: String?
    @State private var error: String?
    @State private var wait = 0
    @FocusState private var codeFocused: Bool

    private var address: String { status[channel].address ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact {
                Label {
                    Text("Confirm your \(channel.noun)").font(FishersTheme.headline)
                } icon: {
                    Image(systemName: channel.systemImage).foregroundStyle(FishersTheme.pitch)
                }
            }

            if status.channels.count > 1 {
                Picker("Confirm by", selection: $channel) {
                    ForEach(status.channels) { Text($0 == .email ? "Email" : "Phone").tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: channel) { _, _ in
                    code = ""
                    note = nil
                    error = nil
                }
            }

            Text("Enter the 6-digit code we \(channel.sentVerb) to **\(address)**.")
                .font(FishersTheme.subhead)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: FishersTheme.space1) {
                TextField("••••••", text: $code)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .frame(minHeight: FishersTheme.minTap)
                    .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Verification code")
                    .onChange(of: code) { _, typed in
                        // Digits only, six at most — and a full code submits
                        // itself, the way the system keyboard's suggestion does.
                        let digits = String(typed.filter(\.isNumber).prefix(6))
                        if digits != typed { code = digits }
                        if digits.count == 6 { Task { await confirm() } }
                    }

                Button {
                    Task { await confirm() }
                } label: {
                    Group {
                        if busy { ProgressView() } else { Text("Confirm").font(FishersTheme.headline) }
                    }
                    .frame(minWidth: 88, minHeight: FishersTheme.minTap)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 6 || busy)
            }

            Button {
                Task { await send() }
            } label: {
                Text(wait > 0 ? "Send a new code in \(wait)s" : "Send a new code")
                    .font(FishersTheme.subhead.weight(.semibold))
                    .frame(minHeight: FishersTheme.minTap)
            }
            // Borderless, or inside a list row a default button claims the
            // whole row and the code field underneath it stops taking taps.
            .buttonStyle(.borderless)
            .disabled(wait > 0)

            if let note {
                Text(note).font(FishersTheme.footnote).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(FishersTheme.footnote).foregroundStyle(FishersTheme.unavailable)
            }
        }
        .onAppear { channel = status.channels.first ?? .email }
        .task(id: wait) {
            guard wait > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            wait -= 1
        }
    }

    private func send() async {
        error = nil
        note = nil
        do {
            let sent = try await FishersAPI.sendVerificationCode(channel)
            note = "New code \(channel.sentVerb) to \(sent.sentTo)."
            wait = sent.resendAfter
            code = ""
            codeFocused = true
        } catch {
            let message = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
            // "you can ask for another in 42s" reads better as a countdown.
            if let seconds = Self.secondsToWait(in: message) {
                wait = seconds
            } else {
                self.error = message
            }
        }
    }

    private func confirm() async {
        guard code.count == 6, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            onVerified(try await FishersAPI.confirmVerification(channel, code: code))
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? "That code did not work"
            code = ""
            codeFocused = true
        }
    }

    static func secondsToWait(in message: String) -> Int? {
        guard let range = message.range(of: #"in (\d+)s"#, options: .regularExpression) else { return nil }
        return Int(message[range].filter(\.isNumber))
    }
}
