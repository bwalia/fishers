import XCTest
@testable import Fishers

/// `GET /marketplace/{id}` flattens the product's fields into the same object
/// as the seller's, so `MarketListing` decodes a `Product` from its own
/// container rather than from a nested key. That is exactly the kind of thing
/// that keeps working until somebody nests it, and then empties the screen
/// rather than one field — so the payload is pinned to a real response.
final class MarketListingDecodingTests: XCTestCase {
    /// Copied from `GET /api/v1/marketplace/{id}` against a seeded local API,
    /// as somebody who is not selling it sees it.
    private let buyersCopy = """
    {
      "id": "e823fb46-36f5-40a5-aa46-50fc5e610433",
      "club_id": "4032a677-8e3c-4e10-9f22-58116d4d74b3",
      "name": "Gray-Nicolls Predator 5 Star",
      "description": "One season of Saturdays. Knocked in, no cracks.",
      "price_cents": 8500,
      "currency": "GBP",
      "category": "equipment",
      "stock": 1,
      "active": true,
      "created_at": "2026-09-29T06:24:59.661963Z",
      "condition": "used",
      "condition_note": "Light wear on the toe.",
      "size": "Short Handle",
      "brand": "Gray-Nicolls",
      "photos": ["https://example.test/a.jpg", "https://example.test/b.jpg"],
      "listed_publicly": true,
      "collection_note": "Clubhouse, Barn Lane, Tuesday evenings.",
      "negotiable": true,
      "listed_by": "557b2d67-8013-44f8-bb4e-91f43f9969da",
      "show_contact": true,
      "club_name": "Lions CC",
      "seller_name": "Priya Raman",
      "seller_email": "saaee93@t.test",
      "seller_phone": null,
      "mine": false,
      "enquiries": null
    }
    """

    private func decode(_ json: String) throws -> MarketListing {
        try FishersJSONDecoder.make().decode(MarketListing.self, from: Data(json.utf8))
    }

    func testDecodesTheFlattenedProduct() throws {
        let listing = try decode(buyersCopy)
        XCTAssertEqual(listing.product.name, "Gray-Nicolls Predator 5 Star")
        XCTAssertEqual(listing.product.priceCents, 8500)
        XCTAssertEqual(listing.product.condition, "used")
        XCTAssertEqual(listing.product.conditionNote, "Light wear on the toe.")
        XCTAssertEqual(listing.product.size, "Short Handle")
        XCTAssertEqual(listing.product.brand, "Gray-Nicolls")
        XCTAssertEqual(listing.product.photos?.count, 2)
        XCTAssertEqual(listing.product.collectionNote, "Clubhouse, Barn Lane, Tuesday evenings.")
        XCTAssertEqual(listing.product.negotiable, true)
        XCTAssertEqual(listing.clubName, "Lions CC")
        XCTAssertEqual(listing.sellerName, "Priya Raman")
    }

    /// The whole point of the ownership split: a buyer must not be offered
    /// their own listing's actions, and a seller must not be told how many
    /// rivals a buyer has.
    func testABuyerIsNotTheSeller() throws {
        let listing = try decode(buyersCopy)
        XCTAssertFalse(listing.mine)
        XCTAssertNil(listing.enquiries)
    }

    func testTheSellerSeesTheirOwnListing() throws {
        let json = buyersCopy
            .replacingOccurrences(of: "\"mine\": false", with: "\"mine\": true")
            .replacingOccurrences(of: "\"enquiries\": null", with: "\"enquiries\": 1")
        let listing = try decode(json)
        XCTAssertTrue(listing.mine)
        XCTAssertEqual(listing.enquiries, 1)
    }

    /// Contact details are withheld unless the seller asked for them to be
    /// shown. Verified against the API: the keys are still sent, holding null.
    func testContactDetailsAreNullWhenWithheld() throws {
        let listing = try decode(
            buyersCopy.replacingOccurrences(
                of: "\"seller_email\": \"saaee93@t.test\"",
                with: "\"seller_email\": null"
            )
        )
        XCTAssertNil(listing.sellerEmail)
        XCTAssertNil(listing.sellerPhone)
        // The name is not a contact detail — it is what the thread is titled
        // with, so it arrives either way.
        XCTAssertEqual(listing.sellerName, "Priya Raman")
    }

    /// And if the server ever stops sending the keys at all — a
    /// `skip_serializing_if` is one line away — that must decode too, not throw.
    func testAnAbsentContactKeyStillDecodes() throws {
        let stripped = buyersCopy
            .split(separator: "\n")
            .filter { !$0.contains("\"seller_email\"") && !$0.contains("\"seller_phone\"") }
            .joined(separator: "\n")
        let listing = try decode(stripped)
        XCTAssertNil(listing.sellerEmail)
        XCTAssertNil(listing.sellerPhone)
    }

    /// The labels the screen prints, which are the reason a buyer can tell a
    /// fixed price from one worth haggling over.
    func testTheLabelsAPersonReads() throws {
        let listing = try decode(buyersCopy)
        XCTAssertEqual(listing.product.priceLine, "£85.00 or near offer")
        XCTAssertEqual(listing.product.conditionLabel, "Second-hand")
        XCTAssertEqual(listing.product.categoryLabel, "Equipment")
        // One of a used thing is "One only", not "1 available" — the phrase a
        // person would use about a single second-hand bat.
        XCTAssertEqual(listing.product.availability, "One only")
        XCTAssertFalse(listing.product.isSold)
    }

    func testSoldIsStockZeroRatherThanAMissingStock() throws {
        let noStock = try decode(buyersCopy.replacingOccurrences(of: "\"stock\": 1", with: "\"stock\": null"))
        XCTAssertFalse(noStock.product.isSold)
        XCTAssertEqual(noStock.product.availability, "On request")

        let gone = try decode(buyersCopy.replacingOccurrences(of: "\"stock\": 1", with: "\"stock\": 0"))
        XCTAssertTrue(gone.product.isSold)
        XCTAssertEqual(gone.product.availability, "Sold")
    }
}
