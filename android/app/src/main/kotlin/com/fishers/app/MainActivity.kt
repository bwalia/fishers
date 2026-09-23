package com.fishers.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.theme.FishersTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val config = (application as FishersApp).config
        setContent {
            FishersTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { inner ->
                    Groundwork(
                        server = config.apiBaseUrl,
                        modifier = Modifier.padding(inner),
                    )
                }
            }
        }
    }
}

/**
 * The scaffold's only screen for now: it proves the theme, the config
 * resolution and the build all work before anything is ported on top of them.
 * `flutter/PARITY.md` says what comes next and in what order.
 */
@Composable
private fun Groundwork(server: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Fishers", style = MaterialTheme.typography.headlineMedium)
        Text(server, style = MaterialTheme.typography.bodySmall)
    }
}

@Preview(showBackground = true)
@Composable
private fun GroundworkPreview() {
    FishersTheme { Groundwork(server = "http://10.0.2.2:7312") }
}
