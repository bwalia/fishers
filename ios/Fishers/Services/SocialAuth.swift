import AuthenticationServices
import Foundation
import SwiftUI
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Result of a social sign-in ready to POST to the API.
struct SocialCredential: Sendable {
    enum Provider: String, Sendable { case google, apple }
    let provider: Provider
    let identityToken: String
    /// Apple only — given + family name on the first authorisation.
    var fullName: String? = nil
    /// Apple only — email when the JWT omits it.
    var email: String? = nil
}

struct SocialAuthConfig: Decodable {
    var enabled: Bool
    var clientId: String?
    var iosClientId: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case clientId = "client_id"
        case iosClientId = "ios_client_id"
    }
}

enum SocialAuthError: LocalizedError {
    case cancelled
    case notConfigured(String)
    case missingToken
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .notConfigured(let what): return "\(what) sign-in is not set up on this server"
        case .missingToken: return "Sign-in did not return a token — try again"
        case .failed(let message): return message
        }
    }
}

@MainActor
enum SocialAuth {
    /// Whether Google can be offered: server has a client id the phone can use.
    static func googleAvailable(_ config: SocialAuthConfig) -> Bool {
        #if canImport(GoogleSignIn)
        return config.enabled && (config.iosClientId != nil || config.clientId != nil)
        #else
        return false
        #endif
    }

    static func signInWithGoogle(config: SocialAuthConfig) async throws -> SocialCredential {
        #if canImport(GoogleSignIn)
        guard let presenter = topViewController() else {
            throw SocialAuthError.failed("Could not present Google sign-in")
        }
        // Prefer the iOS OAuth client; fall back to the web client so a ring
        // that only has GOOGLE_CLIENT_ID still has a chance on device.
        let clientID = config.iosClientId ?? config.clientId
        guard let clientID, !clientID.isEmpty else {
            throw SocialAuthError.notConfigured("Google")
        }
        let configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: config.clientId
        )
        GIDSignIn.sharedInstance.configuration = configuration
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString, !idToken.isEmpty else {
                throw SocialAuthError.missingToken
            }
            return SocialCredential(provider: .google, identityToken: idToken)
        } catch let error as SocialAuthError {
            throw error
        } catch {
            let ns = error as NSError
            if ns.domain == "com.google.GIDSignIn", ns.code == -5 {
                throw SocialAuthError.cancelled
            }
            throw SocialAuthError.failed(error.localizedDescription)
        }
        #else
        throw SocialAuthError.notConfigured("Google")
        #endif
    }

    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
