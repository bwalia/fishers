package com.fishers.app.views.nav

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** A stub route's body while its area is being built. Never shipped: every stub is replaced. */
@Composable
fun NotBuiltYet(what: String) {
    Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
        Text(what, style = MaterialTheme.typography.bodyLarge)
    }
}
