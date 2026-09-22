import XCTest
@testable import Fishers

final class AppConfigTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppConfig.clearAPIBaseURLOverride()
    }

    override func tearDown() {
        AppConfig.clearAPIBaseURLOverride()
        super.tearDown()
    }

    func testOverrideIsReadableOnNextAccess() throws {
        // Skip when the process is pinned by env (UI test / start.sh schemes).
        try XCTSkipIf(AppConfig.environmentPinsAPI, "FISHERS_API_URL pins this process")

        let url = try AppConfig.setAPIBaseURLOverride("https://int.fishers.cloud")
        XCTAssertEqual(url.absoluteString, "https://int.fishers.cloud")
        XCTAssertEqual(AppConfig.apiBaseURL.absoluteString, "https://int.fishers.cloud")
        XCTAssertEqual(AppConfig.storedAPIOverride, "https://int.fishers.cloud")
    }

    /// `scripts/start.sh` persists the Mac's LAN address into the Simulator's
    /// defaults under this very key, so "nothing is stored" is only true on a
    /// clean CI runner — this test failed on any machine that had run the
    /// stack. What clearing actually promises is that *our* override is gone.
    func testClearDropsTheOverride() throws {
        try XCTSkipIf(AppConfig.environmentPinsAPI, "FISHERS_API_URL pins this process")
        let ours = "https://www.fishers.cloud"

        _ = try AppConfig.setAPIBaseURLOverride(ours)
        XCTAssertEqual(AppConfig.storedAPIOverride, ours)
        XCTAssertEqual(AppConfig.apiBaseURL.absoluteString, ours)

        AppConfig.clearAPIBaseURLOverride()
        XCTAssertNotEqual(AppConfig.storedAPIOverride, ours, "the override survived the clear")
        XCTAssertNotEqual(AppConfig.apiBaseURL.absoluteString, ours, "requests still go to it")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride("not a url"))
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride(""))
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride("$(FISHERS_API_BASE_URL)"))
    }

    /// project.yml writes the ports into Info.plist as XcodeGen substitutions.
    /// Generated without them exported, the literal `${API_PORT}` survives into
    /// the build — and a URL with that where a port belongs is not a host we
    /// can reach, so it has to lose to the fallback rather than be dialled.
    func testRejectsAnUnsubstitutedPort() {
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride("http://127.0.0.1:${API_PORT}"))
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride("http://127.0.0.1:${WEB_PORT}"))
    }

    /// The fallback is only reached when every source above it is missing, so
    /// it must name the port the stack actually defaults to rather than a
    /// number that once happened to be right.
    func testFallbackUsesTheDocumentedDefaultPorts() {
        XCTAssertEqual(AppConfig.defaultAPIPort, 7312)
        XCTAssertEqual(AppConfig.defaultWebPort, 7311)
    }
}
