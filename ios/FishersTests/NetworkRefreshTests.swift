import XCTest
@testable import Fishers

/// The session refresh has to be single-flight.
///
/// The API rotates refresh tokens — issuing a new pair revokes the old one — so
/// two requests refreshing at once would send the same token twice and the
/// second would be refused, clearing the keychain and signing a scorer out in
/// the middle of an over.
final class NetworkRefreshTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func makeService() -> NetworkService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return NetworkService(session: URLSession(configuration: config))
    }

    func testConcurrentUnauthorizedCallsRefreshOnlyOnce() async throws {
        let service = makeService()
        await service.setTokens(access: "stale", refresh: "rt-1")

        // Every guarded call is refused once, then succeeds; refresh always works.
        StubProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/auth/refresh") {
                StubProtocol.refreshCount += 1
                let body = #"{"access_token":"fresh","refresh_token":"rt-2"}"#
                return (200, Data(body.utf8))
            }
            let bearer = request.value(forHTTPHeaderField: "Authorization")
            if bearer == "Bearer stale" {
                return (401, Data(#"{"error":"invalid token"}"#.utf8))
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        }

        struct Reply: Decodable { let ok: Bool }

        // Six at once, exactly as a scorer syncing a batch alongside a poll.
        try await withThrowingTaskGroup(of: Reply.self) { group in
            for _ in 0..<6 {
                group.addTask { try await service.request("GET", path: "/clubs") }
            }
            for try await reply in group {
                XCTAssertTrue(reply.ok)
            }
        }

        XCTAssertEqual(
            StubProtocol.refreshCount, 1,
            "six calls refreshing together must share one refresh, not send the rotated token six times"
        )
    }

    /// And the refreshed token is the one used afterwards.
    func testTheRefreshedTokenIsKept() async throws {
        let service = makeService()
        await service.setTokens(access: "stale", refresh: "rt-1")
        StubProtocol.handler = { request in
            if request.url?.path.hasSuffix("/auth/refresh") == true {
                StubProtocol.refreshCount += 1
                return (200, Data(#"{"access_token":"fresh","refresh_token":"rt-2"}"#.utf8))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer stale" {
                return (401, Data("{}".utf8))
            }
            StubProtocol.lastBearer = request.value(forHTTPHeaderField: "Authorization")
            return (200, Data(#"{"ok":true}"#.utf8))
        }
        struct Reply: Decodable { let ok: Bool }
        let _: Reply = try await service.request("GET", path: "/clubs")
        XCTAssertEqual(StubProtocol.lastBearer, "Bearer fresh")
    }
}

/// Answers requests from a closure so the tests never touch the network.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var refreshCount = 0
    nonisolated(unsafe) static var lastBearer: String?

    static func reset() {
        handler = nil
        refreshCount = 0
        lastBearer = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
