package com.fishers.app.views.shop

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.fishers.app.shop.MarketState
import com.fishers.app.shop.Product

/**
 * Kit for sale, across every club.
 *
 * A club with a spare set of pads needs a bigger room than its own membership,
 * so this is the whole app's marketplace rather than one club's shelf. Money is
 * settled in person — a listing is an advert and a reservation, not a checkout.
 */
@Composable
fun MarketplaceScreen(
    state: MarketState,
    onSearch: (String) -> Unit,
    onFilter: (String?) -> Unit,
    onOpen: (Product) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize()) {
        OutlinedTextField(
            value = state.search,
            onValueChange = onSearch,
            label = { Text("Search") },
            placeholder = { Text("Bats, pads, a club shirt") },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        )

        Row(
            Modifier.padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Filter("Everything", state.condition == null) { onFilter(null) }
            Filter("Second-hand", state.condition == "used") { onFilter("used") }
            Filter("Brand new", state.condition == "new") { onFilter("new") }
        }

        when {
            state.isFirstLoad && state.isLoading ->
                Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }

            state.error != null && state.listings.isEmpty() ->
                Box(Modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
                    Text(state.error, style = MaterialTheme.typography.bodyMedium)
                }

            state.listings.isEmpty() -> Empty(searching = state.search.isNotBlank())

            else -> LazyColumn(Modifier.fillMaxSize()) {
                items(state.listings, key = { it.id }) { product ->
                    ListingRow(product) { onOpen(product) }
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
private fun Filter(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(selected = selected, onClick = onClick, label = { Text(label) })
}

@Composable
private fun Empty(searching: Boolean) {
    Box(Modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                if (searching) "Nothing matched that." else "Nothing is for sale yet.",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                if (searching) {
                    "Try a shorter search, or look through everything."
                } else {
                    "When a club lists a bat or a spare set of pads, it turns up here."
                },
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

/**
 * One line in the list: the photograph if there is one, what it is, and what it
 * costs. Enough to decide whether to open it.
 */
@Composable
private fun ListingRow(product: Product, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            // A row is a touch target, and 44dp is the least one can be.
            .heightIn(min = 72.dp)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val shape = RoundedCornerShape(8.dp)
        if (product.photos.isNotEmpty()) {
            AsyncImage(
                model = product.photos.first(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(60.dp).clip(shape),
            )
        } else {
            Box(
                Modifier
                    .size(60.dp)
                    .clip(shape)
                    .padding(1.dp),
                Alignment.Center,
            ) { Text("—", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)) }
        }

        Column(Modifier.weight(1f)) {
            Text(
                product.name,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(product.priceLine, style = MaterialTheme.typography.bodyMedium)
            val meta = listOfNotNull(product.conditionLabel, product.brand, product.size)
            if (meta.isNotEmpty()) {
                Text(
                    meta.joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        if (product.isSold) {
            Text(
                "Sold",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            )
        }
    }
}
