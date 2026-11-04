package com.fishers.app.views.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.fishers.app.i18n.t

/**
 * Delete this account — the in-app door.
 *
 * Google Play requires that an app which lets people create an account lets
 * them start deleting it from inside the app, as well as from a page on the
 * web, and the privacy policy already says "Profile → Delete account … in the
 * app or on the web". Android had sign-up and no way out, so for this app that
 * sentence was not true. `/me/delete` has been there since iOS needed it.
 *
 * State is held with `remember`, not `rememberSaveable`, on purpose: the
 * password would otherwise be written into the saved-instance bundle.
 */
@Composable
fun DeleteAccountCard(onDelete: (password: String, onError: (String) -> Unit) -> Unit) {
    var open by remember { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun close() {
        open = false
        password = ""
        error = null
    }

    TextButton(onClick = { open = true }) {
        Text(t("cl.delete_account"), color = MaterialTheme.colorScheme.error)
    }

    if (open) {
        AlertDialog(
            onDismissRequest = { if (!busy) close() },
            title = { Text(t("cl.delete_account")) },
            text = {
                Column {
                    Text(t("cl.this_cannot_be_undone_type_your_passwo"))
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = password,
                        // The last attempt's reason is about the last attempt.
                        onValueChange = { password = it; error = null },
                        label = { Text(t("cl.your_password")) },
                        singleLine = true,
                        enabled = !busy,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    )
                    error?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(it, color = MaterialTheme.colorScheme.error)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !busy,
                    onClick = {
                        busy = true
                        error = null
                        onDelete(password) { message ->
                            error = message
                            busy = false
                        }
                    },
                ) {
                    Text(
                        if (busy) t("ld.deleting") else t("ld.delete_my_account"),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(enabled = !busy, onClick = { close() }) { Text(t("sc.cancel")) }
            },
        )
    }
}
