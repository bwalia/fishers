package com.fishers.app.views.shop

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
    onReserve: () -> Unit,
    onAsk: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val listing = state.listing
    if (listing == null) {
        Box(modifier.fillMaxSize(), Alignment.Center) {
            if (state.isLoading) {
                CircularProgressIndicator()
            } else {
                Text(
                    state.error ?: "That listing is not available.",
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
    }
}

@Composable
private fun Header(listing: MarketListing) {
    val product = listing.product
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Tag(product.categoryLabel)
            product.conditionLabel?.let { Tag(it) }
            if (product.negotiable && !product.isSold) Tag("Open to offers")
        }
        Text(listing.name, style = MaterialTheme.typography.headlineSmall)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                product.priceLabel,
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            if (product.negotiable) {
                Text(
                    "or near offer",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
        }
        Text(
            if (product.isSold) "Sold — no longer available" else product.availability,
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
                    Text("Reserved for you.", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "The seller has been told. Arrange collection with them and pay them " +
                            "directly — nothing has been taken online.",
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
                        listing.product.isSold -> "Already gone"
                        state.reserving -> "Reserving…"
                        else -> "Reserve it"
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
                        listing.product.negotiable -> "Make an offer"
                        else -> "Ask a question"
                    },
                )
            }
            Text(
                "Nothing is paid online. Reserving tells the seller you want it; you settle up " +
                    "when you collect.",
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
                Text(
                    "Sold by",
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
                Text(
                    "Happy to be contacted directly",
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
            label = { Text("This is your listing") },
            colors = AssistChipDefaults.assistChipColors(
                disabledLabelColor = MaterialTheme.colorScheme.primary,
            ),
        )
        Text(
            "This is exactly how buyers see it.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Stat("People asking", "$asked", Modifier.weight(1f))
            Stat("Photographs", "${listing.photos.size}", Modifier.weight(1f))
            Stat("Visible to", if (listing.listedPublicly) "Every club" else "Your club", Modifier.weight(1f))
        }
        Text(
            when {
                asked == 0 -> "Nobody has asked about it yet. Questions arrive in Chats."
                asked == 1 -> "One person has asked about it — the message is in Chats."
                else -> "$asked people have asked about it. The conversations are in Chats."
            },
            style = MaterialTheme.typography.bodySmall,
        )
        if (listing.photos.isEmpty()) {
            Card(colors = CardDefaults.cardColors(MaterialTheme.colorScheme.secondaryContainer)) {
                Text(
                    "It has no photographs. A listing without one is usually scrolled past — " +
                        "adding a couple is the single thing most likely to sell it.",
                    Modifier.padding(12.dp),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        // Editing a listing is on the web for now, so this says where rather
        // than offering a button that would go nowhere.
        Text(
            "Change the price, add photographs or mark it sold on the website.",
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

    Block("Description") {
        Text(
            product.description?.takeIf { it.isNotBlank() }
                ?: if (listing.mine) {
                    "No description was written. Adding one helps it sell."
                } else {
                    "No description was written. Ask the seller if you need to know more."
                },
            style = MaterialTheme.typography.bodyMedium,
        )
    }

    Block("Details") {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Spec("Category", product.categoryLabel)
            product.conditionLabel?.let { Spec("Condition", it) }
            product.brand?.let { Spec("Make", it) }
            product.size?.let { Spec("Size", it) }
            Spec("How many", product.availability)
            product.conditionNote?.let { Spec("Wear and damage", it) }
        }
    }

    Block("Where to collect it") {
        Column {
            Text(listing.clubName, style = MaterialTheme.typography.titleSmall)
            Text(
                product.collectionNote
                    ?: "The seller has not said where yet — ask them before you travel.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }

    if (!listing.mine) {
        Block("How buying works") {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Step(
                    1, "Ask anything you need to.",
                    "Messages go to the seller here in the app." +
                        if (product.negotiable) {
                            " The price is open to offers, so say what you would pay."
                        } else {
                            ""
                        },
                )
                Step(
                    2, "Reserve it.",
                    "That holds it for you and tells the seller — it does not charge you anything.",
                )
                Step(
                    3, "Collect and pay in person.",
                    "Cash or transfer, directly to the seller. No money goes through this app.",
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
                Text(
                    "No photograph",
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
                contentDescription = "$title — photograph ${page + 1} of ${photos.size}",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        if (photos.size > 1) {
            // A count rather than dots: a screen reader can say "2 of 6", and
            // six identical dots tell somebody with low vision nothing.
            Text(
                "${pager.currentPage + 1} of ${photos.size}",
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
