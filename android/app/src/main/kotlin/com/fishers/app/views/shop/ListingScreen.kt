package com.fishers.app.views.shop

import com.fishers.app.i18n.t
import com.fishers.app.net.FishersApi
import com.fishers.app.safety.ReportSubjectKind
import com.fishers.app.views.safety.ReportOrBlock

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.fishers.app.shop.ListingState
import com.fishers.app.shop.MarketListing

/**
 * One thing for sale, in full.
 *
 * Two readers, one screen. A buyer needs to know what it is, what state it is
 * in, where to collect it and who to ask — each of those under its own heading,
 * because an unlabelled paragraph under a price is not obviously the
 * description, and somebody who has never bought anything second-hand should
 * not have to work it out.
 *
 * The seller needs none of that. They wrote it. Offering them "Message the
 * seller" on their own advert is the app saying it does not know who they are,
 * and reserving it would take their own kit off the marketplace and then notify
 * them about themselves. So they get their own panel instead.
 */
@Composable
fun ListingScreen(
    state: ListingState,
    api: FishersApi,
    onReserve: () -> Unit,
    onAsk: () -> Unit,
    onBlocked: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val listing = state.listing
    if (listing == null) {
        Box(modifier.fillMaxSize(), Alignment.Center) {
            if (state.isLoading) {
                CircularProgressIndicator()
            } else {
                Text(
                    state.error ?: t("lc.that_listing_is_not_available"),
                    Modifier.padding(32.dp),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        return
    }

    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Gallery(listing.photos, listing.name)
        Header(listing)

        if (listing.mine) OwnerPanel(listing) else BuyerPanel(state, listing, onReserve, onAsk)

        state.error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        Sections(listing)

        // A listing is the one place a stranger puts words and a photograph in
        // front of you, so it is the one that most needs this. Not on your own
        // advert: there is nobody there to report but yourself. Blocking steps
        // back to the marketplace, which no longer holds it.
        if (!listing.mine) {
            ReportOrBlock(
                api = api,
                kind = ReportSubjectKind.LISTING,
                subjectId = listing.id,
                personId = listing.listedBy,
                personName = listing.sellerName,
                onBlocked = { onBlocked() },
            )
        }
    }
}

@Composable
private fun Header(listing: MarketListing) {
    val product = listing.product
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Tag(product.categoryLabel)
            product.conditionLabel?.let { Tag(it) }
            if (product.negotiable && !product.isSold) Tag(t("sh.open_to_offers"))
        }
        Text(listing.name, style = MaterialTheme.typography.headlineSmall)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                product.priceLabel,
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            if (product.negotiable) {
                Text(t("sh.or_near_offer"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
        }
        Text(
            if (product.isSold) t("lc.sold_no_longer_available") else product.availability,
            style = MaterialTheme.typography.bodyMedium,
            color = if (product.isSold) {
                MaterialTheme.colorScheme.error
            } else {
                MaterialTheme.colorScheme.primary
            },
        )
    }
}

/** What somebody who might buy it can do. */
@Composable
private fun BuyerPanel(
    state: ListingState,
    listing: MarketListing,
    onReserve: () -> Unit,
    onAsk: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (state.reserved) {
            Card(colors = CardDefaults.cardColors(MaterialTheme.colorScheme.primaryContainer)) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(t("sh.reserved_for_you"), style = MaterialTheme.typography.titleSmall)
                    Text(
                        t("sh.seller_has_been_told"),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        } else {
            Button(
                onClick = onReserve,
                enabled = !state.reserving && !listing.product.isSold,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                Text(
                    when {
                        listing.product.isSold -> t("lc.already_gone")
                        state.reserving -> t("lc.reserving")
                        else -> t("lc.reserve_it")
                    },
                )
            }
            OutlinedButton(
                onClick = onAsk,
                enabled = !state.asking,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                Text(
                    when {
                        state.asking -> "Opening…"
                        listing.product.negotiable -> t("lc.make_an_offer")
                        else -> t("lc.ask_a_question")
                    },
                )
            }
            Text(
                t("sh.nothing_paid_online"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(40.dp),
            ) {
                Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text(
                        (listing.sellerName ?: listing.clubName).take(1).uppercase(),
                        color = MaterialTheme.colorScheme.onPrimary,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            Column {
                Text(t("sh.sold_by"),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
                Text(
                    listing.sellerName ?: listing.clubName,
                    style = MaterialTheme.typography.titleSmall,
                )
                if (listing.sellerName != null) {
                    Text(
                        listing.clubName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    )
                }
            }
        }

        // Shown only when the seller asked for it — the server leaves these out
        // otherwise, so there is nothing here to forget to hide.
        if (listing.sellerPhone != null || listing.sellerEmail != null) {
            Column {
                Text(t("sh.happy_to_be_contacted"),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
                listing.sellerPhone?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                listing.sellerEmail?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
}

/** The same listing, to the person selling it. */
@Composable
private fun OwnerPanel(listing: MarketListing) {
    val asked = listing.enquiries ?: 0
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        AssistChip(
            onClick = {},
            enabled = false,
            label = { Text(t("sh.this_is_your_listing")) },
            colors = AssistChipDefaults.assistChipColors(
                disabledLabelColor = MaterialTheme.colorScheme.primary,
            ),
        )
        Text(t("sh.this_is_exactly_how_buyers_see_it"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Stat(t("sh.people_asking"), "$asked", Modifier.weight(1f))
            Stat(t("sh.photographs"), "${listing.photos.size}", Modifier.weight(1f))
            Stat(t("sh.visible_to"), if (listing.listedPublicly) t("lc.every_club") else t("lc.your_club"), Modifier.weight(1f))
        }
        Text(
            when {
                asked == 0 -> t("sh.nobody_has_asked_about_it_yet_question")
                asked == 1 -> t("cl.one_person_has_asked")
                else -> "$asked people have asked about it. The conversations are in Chats."
            },
            style = MaterialTheme.typography.bodySmall,
        )
        if (listing.photos.isEmpty()) {
            Card(colors = CardDefaults.cardColors(MaterialTheme.colorScheme.secondaryContainer)) {
                Text(
                    t("sh.no_photographs_advice"),
                    Modifier.padding(12.dp),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        // Editing a listing is on the web for now, so this says where rather
        // than offering a button that would go nowhere.
        Text(t("sh.change_price_on_website"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
    }
}

@Composable
private fun Stat(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = modifier,
    ) {
        Column(
            Modifier.padding(vertical = 8.dp, horizontal = 4.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
    }
}

/** Everything worth reading, each piece under its own heading. */
@Composable
private fun Sections(listing: MarketListing) {
    val product = listing.product

    Block(t("sh.description")) {
        Text(
            product.description?.takeIf { it.isNotBlank() }
                ?: if (listing.mine) {
                    t("sh.no_description_adding_helps")
                } else {
                    t("sh.no_description_ask_seller")
                },
            style = MaterialTheme.typography.bodyMedium,
        )
    }

    Block(t("sh.details")) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Spec(t("sh.category"), product.categoryLabel)
            product.conditionLabel?.let { Spec(t("sh.condition"), it) }
            product.brand?.let { Spec(t("sh.make"), it) }
            product.size?.let { Spec(t("sh.size"), it) }
            Spec(t("sh.how_many"), product.availability)
            product.conditionNote?.let { Spec(t("sh.wear_and_damage"), it) }
        }
    }

    Block(t("sh.where_to_collect_it")) {
        Column {
            Text(listing.clubName, style = MaterialTheme.typography.titleSmall)
            Text(
                product.collectionNote
                    ?: t("lc.the_seller_has_not_said_where_yet_ask"),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }

    if (!listing.mine) {
        Block(t("sh.how_buying_works")) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Step(
                    1, t("sh.ask_anything_you_need_to"),
                    t("fin.messages_go_to_seller") +
                        if (product.negotiable) {
                            " The price is open to offers, so say what you would pay."
                        } else {
                            ""
                        },
                )
                Step(
                    2, t("sh.reserve_it"),
                    t("sh.holds_it_for_you"),
                )
                Step(
                    3, t("sh.collect_and_pay_in_person"),
                    t("sh.cash_or_transfer_directly_to_the_selle"),
                )
            }
        }
    }
}

/** Every photograph, one at a time — swipe through them. */
@Composable
private fun Gallery(photos: List<String>, title: String) {
    val shape = RoundedCornerShape(14.dp)
    if (photos.isEmpty()) {
        Surface(
            shape = shape,
            color = MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.fillMaxWidth().height(200.dp),
        ) {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                Text(t("sh.no_photograph"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
            }
        }
        return
    }

    val pager = rememberPagerState { photos.size }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        HorizontalPager(
            state = pager,
            modifier = Modifier.fillMaxWidth().height(260.dp).clip(shape),
        ) { page ->
            AsyncImage(
                model = photos[page],
                contentDescription = t(
                    "sc.photograph_n_of_m",
                    vars = mapOf("title" to title, "n" to page + 1, "total" to photos.size),
                ),
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        if (photos.size > 1) {
            // A count rather than dots: a screen reader can say "2 of 6", and
            // six identical dots tell somebody with low vision nothing.
            Text(
                t("rest.photo_n_of_total", vars = mapOf("n" to pager.currentPage + 1, "total" to photos.size)),
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
        }
    }
}

@Composable
private fun Tag(text: String) {
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Text(
            text,
            Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
private fun Block(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                title.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
            content()
        }
    }
}

@Composable
private fun Spec(label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            label,
            Modifier.width(130.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun Step(number: Int, title: String, detail: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer) {
            Box(Modifier.size(22.dp), Alignment.Center) {
                Text("$number", style = MaterialTheme.typography.labelMedium)
            }
        }
        Column {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(
                detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
        }
    }
}
