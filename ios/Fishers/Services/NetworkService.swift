import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(Error)
    case unauthorized
    case empty
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding(let e): return "Decode error: \(e.localizedDescription)"
        case .unauthorized: return "Please sign in again"
        case .empty: return "Empty response"
        case .unreachable(let detail):
            return "Cannot reach API at \(AppConfig.apiBaseURL.absoluteString) — is it running? (\(detail))"
        }
    }

    /// The sentence to put in front of somebody.
    ///
    /// The API answers a refusal as `{"error": "..."}`, written for a person to
    /// read. Showing `HTTP 400: {"error":"that is not a JPEG…"}` throws that
    /// away and hands them the plumbing instead.
    var friendlyMessage: String {
        if case .http(_, let body) = self,
           let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String,
           !message.isEmpty {
            return message
        }
        return errorDescription ?? "Something went wrong."
    }
}

/// Shared JSON decoder for API payloads. Accepts ISO-8601 with or without
/// fractional seconds (chrono/Postgres default), which Foundation's plain
/// `.iso8601` strategy rejects.
enum FishersJSONDecoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeISO8601Date)
        return decoder
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func decodeISO8601Date(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = iso8601Fractional.date(from: raw) ?? iso8601Plain.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unrecognized date: \(raw)"
        )
    }
}

actor NetworkService {
    static let shared = NetworkService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var accessToken: String?
    private var refreshToken: String?
    /// The refresh in flight, if there is one. See `refreshAccessToken`.
    private var refreshTask: Task<Void, Error>?

    init(session: URLSession = .shared) {
        self.session = session
        decoder = FishersJSONDecoder.make()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func setTokens(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
        if let access { KeychainStore.set(access, forKey: "access_token") }
        if let refresh { KeychainStore.set(refresh, forKey: "refresh_token") }
        if access == nil { KeychainStore.delete("access_token") }
        if refresh == nil { KeychainStore.delete("refresh_token") }
    }

    func loadTokensFromKeychain() {
        accessToken = KeychainStore.get("access_token")
        refreshToken = KeychainStore.get("refresh_token")
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        KeychainStore.delete("access_token")
        KeychainStore.delete("refresh_token")
    }

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        authorized: Bool = true
    ) async throws -> T {
        let data = try await rawRequest(
            method, path: path, body: body, authorized: authorized
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func requestVoid(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        authorized: Bool = true
    ) async throws {
        _ = try await rawRequest(
            method, path: path, body: body, authorized: authorized
        )
    }

    /// Send one file as multipart/form-data.
    ///
    /// Separate from `rawRequest` because the body is not JSON and the
    /// Content-Type has to carry the boundary. Deliberately not general: one
    /// file, one field, which is every upload the app makes.
    func upload<T: Decodable>(
        path: String,
        fileName: String,
        mimeType: String,
        data fileData: Data,
        fieldName: String = "file"
    ) async throws -> T {
        guard let url = URL(string: AppConfig.apiBaseURL.absoluteString + AppConfig.apiVersionPrefix + path) else {
            throw APIError.invalidURL
        }
        // A fresh token first: a multipart retry would mean rebuilding the body,
        // and a photo is big enough that sending it twice is worth avoiding.
        if accessToken == nil, refreshToken != nil {
            try await refreshAccessToken()
        }

        let boundary = "fishers.\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                throw APIError.unreachable(error.localizedDescription)
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.empty }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func rawRequest(
        _ method: String,
        path: String,
        body: (any Encodable)?,
        authorized: Bool,
        hasRefreshed: Bool = false
    ) async throws -> Data {
        guard let url = URL(string: AppConfig.apiBaseURL.absoluteString + AppConfig.apiVersionPrefix + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                throw APIError.unreachable(error.localizedDescription)
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.empty }

        // Refresh once and retry once. Without the guard, a server that keeps
        // answering 401 sends this into an unbounded recursion.
        if http.statusCode == 401, authorized, !hasRefreshed, refreshToken != nil {
            try await refreshAccessToken()
            return try await rawRequest(
                method, path: path, body: body, authorized: true, hasRefreshed: true
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.http(http.statusCode, bodyText)
        }
        return data
    }

    /// Renew the session, one at a time.
    ///
    /// An actor serialises calls but still suspends at every `await`, so two
    /// requests answered 401 together would each reach the network with the
    /// same refresh token. The server rotates them — issuing a new pair revokes
    /// the old one — so the second would be refused and the loser would clear
    /// the keychain and sign the scorer out mid-match. Whoever asks second
    /// waits on the refresh already running instead.
    private func refreshAccessToken() async throws {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func performRefresh() async throws {
        guard let refreshToken else { throw APIError.unauthorized }
        struct Body: Encodable { let refresh_token: String }
        struct Resp: Decodable {
            let access_token: String
            let refresh_token: String
        }
        // Bypass authorized path to avoid recursion
        guard let url = URL(string: AppConfig.apiBaseURL.absoluteString + AppConfig.apiVersionPrefix + "/auth/refresh") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(Body(refresh_token: refreshToken))
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            clearTokens()
            throw APIError.unauthorized
        }
        let tokens = try decoder.decode(Resp.self, from: data)
        setTokens(access: tokens.access_token, refresh: tokens.refresh_token)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ value: any Encodable) {
        encodeFunc = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
