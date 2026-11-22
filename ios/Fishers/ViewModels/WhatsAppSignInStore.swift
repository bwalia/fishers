import Foundation

/// Signing in with a mobile number and a six-digit code sent on WhatsApp.
///
/// Offered only while the server says it is switched on. Every refusal is
/// the server's own sentence; `code` decides what happens next — a wrong
/// code clears the boxes, `whatsapp_off` takes the option away.
@MainActor
final class WhatsAppSignInStore: ObservableObject {
    enum Step: Equatable {
        case number
        case code
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var step: Step = .number
    @Published var phone = ""
    @Published var code = ""
    @Published private(set) var isWorking = false
    /// The server's sentence for the last refusal.
    @Published private(set) var problem: String?
    /// When another code can be asked for.
    @Published private(set) var resendAt: Date?

    static let codeLength = 6

    private let network: NetworkService

    init(network: NetworkService = .shared) {
        self.network = network
    }

    /// Asked once when the sign-in screen opens. Any failure reads as off:
    /// an option that might not work is worse than one not offered.
    func checkEnabled() async {
        isEnabled = (try? await FishersAPI.whatsAppSignIn(network: network).enabled) ?? false
    }

    private var trimmedPhone: String { phone.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Loose on purpose: the server decides what a number is (`bad_phone`).
    var canSendCode: Bool { trimmedPhone.filter(\.isNumber).count >= 7 && !isWorking }

    var canVerify: Bool { code.filter(\.isNumber).count == Self.codeLength && !isWorking }

    func canResend(at now: Date = .now) -> Bool { resendAt.map { now >= $0 } ?? true }

    /// Keeps only digits, and no more than six, as the code is typed or pasted.
    func setCode(_ typed: String) {
        code = String(typed.filter(\.isNumber).prefix(Self.codeLength))
    }

    func sendCode(now: Date = .now) async {
        guard canSendCode else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            let sent = try await FishersAPI.startWhatsAppSignIn(phone: trimmedPhone, network: network)
            step = .code
            code = ""
            resendAt = now.addingTimeInterval(TimeInterval(sent.resendAfter))
        } catch {
            refused(error)
        }
    }

    /// The tokens, for the session to take on; nil when the code was refused.
    func verify() async -> AuthTokens? {
        guard canVerify else { return nil }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            return try await FishersAPI.verifyWhatsAppSignIn(phone: trimmedPhone, code: code, network: network)
        } catch {
            refused(error)
            return nil
        }
    }

    func useAnotherNumber() {
        step = .number
        code = ""
        problem = nil
        resendAt = nil
    }

    private func refused(_ error: Error) {
        problem = paymentMessage(error)
        switch (error as? APIError)?.code {
        case "wrong_code":
            code = ""
        case "whatsapp_off":
            isEnabled = false
        default:
            break
        }
    }
}
