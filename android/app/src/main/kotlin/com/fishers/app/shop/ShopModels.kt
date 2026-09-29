package com.fishers.app.shop

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * The server's own shape, from `backend/domain/src/order.rs`. Named as the wire
 * names them: these are a contract, not a place to improve on someone's
 * spelling.
 */
@Serializable
data class Product(
    val id: String,
    @SerialName("club_id") val clubId: String,
    val name: String,
    val description: String? = null,
    @SerialName("price_cents") val priceCents: Int,
    val currency: String = "GBP",
    val category: String,
    /**
     * `null` is "on request" — made to order, or a tea urn that does not run
     * out. A second-hand item is almost always 1.
     */
    val stock: Int? = null,
    /** "new" or "used". Absent for the things it does not apply to. */
    val condition: String? = null,
    /**
     * "Light wear on the toe, no cracks." The sentence that decides whether
     * somebody drives an hour to look at it.
     */
    @SerialName("condition_note") val conditionNote: String? = null,
    /**
     * Short Handle, Harrow, Youth Large — free text, because bat, pad and
     * glove sizes share no vocabulary.
     */
    val size: String? = null,
    val brand: String? = null,
    val photos: List<String> = emptyList(),
    /** Whether it appears outside the club. */
    @SerialName("listed_publicly") val listedPublicly: Boolean = false,
    @SerialName("collection_note") val collectionNote: String? = null,
    /**
     * Whether the price is the price. Second-hand kit gets haggled over, and a
     * buyer who cannot tell either overpays or does not ask.
     */
    val negotiable: Boolean = false,
) {
    val priceLabel: String
        get() = runCatching {
            NumberFormat.getCurrencyInstance(Locale.UK).apply {
                this.currency = Currency.getInstance(this@Product.currency)
            }.format(priceCents / 100.0)
        }.getOrElse { "%.2f %s".format(priceCents / 100.0, currency) }

    /**
     * "£45.00", or "£45.00 or near offer" when the seller will haggle. The
     * difference decides whether somebody asks at all.
     */
    val priceLine: String get() = if (negotiable) "$priceLabel or near offer" else priceLabel

    val isSold: Boolean get() = stock == 0

    val availability: String
        get() = when {
            stock == null -> "On request"
            stock == 0 -> "Sold"
            stock == 1 && condition == "used" -> "One only"
            else -> "$stock available"
        }

    val conditionLabel: String?
        get() = when (condition) {
            "used" -> "Second-hand"
            "new" -> "Brand new"
            else -> null
        }

    val categoryLabel: String
        get() = when (category) {
            "equipment" -> "Equipment"
            "merchandise" -> "Merchandise"
            else -> category.replaceFirstChar { it.uppercase() }
        }
}

/**
 * One listing as its own screen shows it: the product, plus who is selling it
 * and whether that is you.
 *
 * The product's fields arrive flattened into the same object, so this repeats
 * them rather than nesting — `@SerialName` keeps it honest either way.
 *
 * `mine` is answered by the server rather than by comparing ids here, because
 * "mine" is not only "I posted it": a secretary who runs the club's shop is
 * looking at their own listing too, and that rule belongs where the
 * permissions already live.
 */
@Serializable
data class MarketListing(
    val id: String,
    @SerialName("club_id") val clubId: String,
    val name: String,
    val description: String? = null,
    @SerialName("price_cents") val priceCents: Int,
    val currency: String = "GBP",
    val category: String,
    val stock: Int? = null,
    val condition: String? = null,
    @SerialName("condition_note") val conditionNote: String? = null,
    val size: String? = null,
    val brand: String? = null,
    val photos: List<String> = emptyList(),
    @SerialName("listed_publicly") val listedPublicly: Boolean = false,
    @SerialName("collection_note") val collectionNote: String? = null,
    val negotiable: Boolean = false,
    @SerialName("club_name") val clubName: String,
    @SerialName("seller_name") val sellerName: String? = null,
    /**
     * Only when the seller asked for their details to be shown. `null`
     * otherwise, and the buyer is pointed at the message thread instead.
     */
    @SerialName("seller_email") val sellerEmail: String? = null,
    @SerialName("seller_phone") val sellerPhone: String? = null,
    val mine: Boolean = false,
    /** How many people have asked about it. Only sent to the seller. */
    val enquiries: Int? = null,
) {
    /** The same derived labels, without a second copy of the arithmetic. */
    val product: Product
        get() = Product(
            id = id, clubId = clubId, name = name, description = description,
            priceCents = priceCents, currency = currency, category = category, stock = stock,
            condition = condition, conditionNote = conditionNote, size = size, brand = brand,
            photos = photos, listedPublicly = listedPublicly, collectionNote = collectionNote,
            negotiable = negotiable,
        )
}

/**
 * The answer to asking about a listing: which thread to open, and whether it is
 * a new one or the one they already had.
 */
@Serializable
data class EnquiryStarted(
    @SerialName("conversation_id") val conversationId: String,
    val started: Boolean,
)

@Serializable
data class OrderItemRequest(
    @SerialName("product_id") val productId: String,
    val quantity: Int,
)

@Serializable
data class PlaceOrderRequest(
    @SerialName("club_id") val clubId: String,
    val items: List<OrderItemRequest>,
)

@Serializable
data class PlacedOrder(val id: String)

@Serializable
data class OrderResponse(val order: PlacedOrder)
