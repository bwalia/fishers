import Foundation

struct Endpoint {
    var method: String = "GET"
    var path: String
    var query: [URLQueryItem] = []
    var body: Data?
    var authenticated: Bool = true

    static func get(_ path: String, query: [URLQueryItem] = []) -> Endpoint {
        Endpoint(method: "GET", path: path, query: query)
    }

    static func post(_ path: String, body: Data? = nil, authenticated: Bool = true) -> Endpoint {
        Endpoint(method: "POST", path: path, body: body, authenticated: authenticated)
    }

    static func patch(_ path: String, body: Data? = nil) -> Endpoint {
        Endpoint(method: "PATCH", path: path, body: body)
    }
}

enum APIConfig {
    static let baseURLDefaultsKey = "apiBaseURL"

    /// Host of the Rust backend; override in UserDefaults (Profile tab) to point at a real deployment.
    static var baseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: baseURLDefaultsKey),
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

    static let apiPrefix = "/api/v1"
}

enum APICoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
