package com.fishers.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.ui.Modifier
import androidx.compose.runtime.remember
import com.fishers.app.chat.ChatListViewModel
import com.fishers.app.chat.ChatThreadViewModel
import com.fishers.app.session.SessionViewModel
import com.fishers.app.theme.FishersTheme
import com.fishers.app.views.RootScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as FishersApp

        setContent {
            FishersTheme {
                val model: SessionViewModel = viewModel(
                    factory = object : ViewModelProvider.Factory {
                        @Suppress("UNCHECKED_CAST")
                        override fun <T : ViewModel> create(modelClass: Class<T>): T =
                            SessionViewModel(app.network.api, app.session) as T
                    },
                )
                Scaffold(modifier = Modifier.fillMaxSize()) { inner ->
                    RootScreen(
                        viewModel = model,
                        chatList = remember { ChatListViewModel(app.network.api) },
                        threadFor = { id -> ChatThreadViewModel(app.network.api, id) },
                        modifier = Modifier.padding(inner),
                    )
                }
            }
        }
    }
}
