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

    func testClearReturnsToDefault() throws {
        try XCTSkipIf(AppConfig.environmentPinsAPI, "FISHERS_API_URL pins this process")

        _ = try AppConfig.setAPIBaseURLOverride("https://www.fishers.cloud")
        AppConfig.clearAPIBaseURLOverride()
        XCTAssertNil(AppConfig.storedAPIOverride)
        XCTAssertEqual(AppConfig.apiBaseURL, AppConfig.defaultAPIBaseURL)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride("not a url"))
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride(""))
        XCTAssertThrowsError(try AppConfig.setAPIBaseURLOverride("$(FISHERS_API_BASE_URL)"))
    }
}
