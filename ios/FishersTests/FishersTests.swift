import XCTest
@testable import Fishers

final class FishersTests: XCTestCase {
    func testAvailabilityStatusCycles() {
        XCTAssertEqual(AvailabilityStatus.available.next(), .maybe)
        XCTAssertEqual(AvailabilityStatus.maybe.next(), .unavailable)
        XCTAssertEqual(AvailabilityStatus.unavailable.next(), .available)
    }

    func testProductPriceLabel() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "club_id": "00000000-0000-0000-0000-000000000002",
          "name": "Tea",
          "description": null,
          "price_cents": 200,
          "currency": "GBP",
          "category": "drink"
        }
        """.data(using: .utf8)!
        let product = try JSONDecoder().decode(Product.self, from: json)
        XCTAssertEqual(product.priceLabel, "£2.00")
    }
}
