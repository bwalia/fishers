package com.fishers.app.shop

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `GET /marketplace/{id}` flattens the product's fields into the same object as
 * the seller's, and sends a good many keys this app does not read. Both are the
 * kind of thing that keeps working until it does not, so the payload is pinned
 * to a real response.
 */
class MarketListingDecodingTest {
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Copied from `GET /api/v1/marketplace/{id}` against a seeded local API, as
     * somebody who is not selling it sees it.
     */
    private val buyersCopy = """
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
    """.trimIndent()

    private fun decode(payload: String) = json.decodeFromString<MarketListing>(payload)

    @Test
    fun `decodes the flattened product`() {
        val listing = decode(buyersCopy)
        assertEquals("Gray-Nicolls Predator 5 Star", listing.name)
        assertEquals(8500, listing.priceCents)
        assertEquals("used", listing.condition)
        assertEquals("Light wear on the toe.", listing.conditionNote)
        assertEquals("Short Handle", listing.size)
        assertEquals("Gray-Nicolls", listing.brand)
        assertEquals(2, listing.photos.size)
        assertEquals("Clubhouse, Barn Lane, Tuesday evenings.", listing.collectionNote)
        assertTrue(listing.negotiable)
        assertEquals("Lions CC", listing.clubName)
        assertEquals("Priya Raman", listing.sellerName)
    }

    /**
     * The whole point of the ownership split: a buyer must not be offered their
     * own listing's actions, and a buyer must not be told how many rivals they
     * have.
     */
    @Test
    fun `a buyer is not the seller`() {
        val listing = decode(buyersCopy)
        assertFalse(listing.mine)
        assertNull(listing.enquiries)
    }

    @Test
    fun `the seller sees their own listing`() {
        val listing = decode(
            buyersCopy
                .replace("\"mine\": false", "\"mine\": true")
                .replace("\"enquiries\": null", "\"enquiries\": 1"),
        )
        assertTrue(listing.mine)
        assertEquals(1, listing.enquiries)
    }

    /**
     * Contact details are withheld unless the seller asked for them to be
     * shown. Verified against the API: the keys are still sent, holding null.
     */
    @Test
    fun `contact details are null when withheld`() {
        val listing = decode(
            buyersCopy.replace("\"seller_email\": \"saaee93@t.test\"", "\"seller_email\": null"),
        )
        assertNull(listing.sellerEmail)
        assertNull(listing.sellerPhone)
        // The name is not a contact detail — it is what the thread is titled
        // with, so it arrives either way.
        assertEquals("Priya Raman", listing.sellerName)
    }

    /**
     * And if the server ever stops sending the keys at all — a
     * `skip_serializing_if` is one line away — that must decode too, not throw.
     */
    @Test
    fun `an absent contact key still decodes`() {
        val stripped = buyersCopy.lines()
            .filterNot { it.contains("\"seller_email\"") || it.contains("\"seller_phone\"") }
            .joinToString("\n")
        val listing = decode(stripped)
        assertNull(listing.sellerEmail)
        assertNull(listing.sellerPhone)
    }

    /**
     * The labels the screen prints, which are the reason a buyer can tell a
     * fixed price from one worth haggling over.
     */
    @Test
    fun `the labels a person reads`() {
        val product = decode(buyersCopy).product
        assertEquals("£85.00 or near offer", product.priceLine)
        assertEquals("Second-hand", product.conditionLabel)
        assertEquals("Equipment", product.categoryLabel)
        // One of a used thing is "One only", not "1 available" — the phrase a
        // person would use about a single second-hand bat.
        assertEquals("One only", product.availability)
        assertFalse(product.isSold)
    }

    @Test
    fun `sold is stock zero rather than a missing stock`() {
        val onRequest = decode(buyersCopy.replace("\"stock\": 1", "\"stock\": null")).product
        assertFalse(onRequest.isSold)
        assertEquals("On request", onRequest.availability)

        val gone = decode(buyersCopy.replace("\"stock\": 1", "\"stock\": 0")).product
        assertTrue(gone.isSold)
        assertEquals("Sold", gone.availability)
    }

    /** The list endpoint sends the same rows without the seller's half. */
    @Test
    fun `the marketplace list decodes too`() {
        val product = json.decodeFromString<Product>(buyersCopy)
        assertEquals("Gray-Nicolls Predator 5 Star", product.name)
        assertEquals(2, product.photos.size)
    }
}
