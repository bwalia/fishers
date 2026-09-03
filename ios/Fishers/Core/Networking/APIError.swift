import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case transport(Error)
    case server(statusCode: Int, message: String?)
    case unauthorized
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        case .server(let code, let message):
            return message ?? "Server error (\(code))."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .decoding:
            return "Unexpected response from the server."
        }
    }
}

struct ServerErrorBody: Decodable {
    var error: String?
    var message: String?
}
