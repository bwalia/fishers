package com.fishers.app.views.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.session.RoleIntent
import com.fishers.app.session.SessionState
import com.fishers.app.theme.FishersTheme

/**
 * Sign in and sign up on one form — `AuthView.swift`.
 *
 * One form rather than two screens, because the commonest thing somebody does
 * here is discover they are on the wrong one. The role question appears only on
 * sign-up, where it is the only thing the app needs to know that it cannot work
 * out later.
 *
 * No social buttons yet: Apple is a settled gap on Android, and Google needs a
 * native SDK and console config that have not landed.
 */
@Composable
fun AuthScreen(
    state: SessionState,
    onSignIn: (identifier: String, password: String) -> Unit,
    onSignUp: (name: String, identifier: String, password: String, role: RoleIntent?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var signingUp by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var identifier by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var role by rememberSaveable { mutableStateOf<RoleIntent?>(null) }

    // Eight is the server's minimum on sign-up; signing in only needs
    // something, because the rule may have changed since the account was made.
    val minPassword = if (signingUp) 8 else 1
    val canSubmit = identifier.isNotBlank() &&
        password.length >= minPassword &&
        (!signingUp || name.isNotBlank()) &&
        !state.isLoading

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            modifier = Modifier.widthIn(max = 480.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Fishers", style = MaterialTheme.typography.headlineLarge)
            Text(
                if (signingUp) "Start playing." else "Welcome back.",
                style = MaterialTheme.typography.bodyLarge,
            )

            if (signingUp) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Your name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                )
            }

            OutlinedTextField(
                value = identifier,
                onValueChange = { identifier = it },
                label = { Text("Email or mobile") },
                supportingText = { Text("Either works — the server sorts out which.") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Next,
                ),
            )

            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password") },
                supportingText = {
                    if (signingUp) Text("Eight characters or more.")
                },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
            )

            if (signingUp) {
                Text("What brings you here?", style = MaterialTheme.typography.titleSmall)
                Column(Modifier.selectableGroup()) {
                    RoleIntent.entries.forEach { option ->
                        RoleOption(
                            selected = role == option,
                            label = option.title,
                            onSelect = { role = option },
                        )
                    }
                }
            }

            state.error?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            Button(
                onClick = {
                    if (signingUp) onSignUp(name, identifier, password, role)
                    else onSignIn(identifier, password)
                },
                enabled = canSubmit,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .height(20.dp)
                            .semantics { contentDescription = "Signing in" },
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text(if (signingUp) "Create account" else "Sign in")
                }
            }

            TextButton(
                onClick = { signingUp = !signingUp },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    if (signingUp) "I already have an account"
                    else "I am new here"
                )
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

/**
 * The whole row is the target, not just the button — a 20dp radio is a hard
 * thing to hit, and `onClick = null` on the button leaves the row to own the
 * click so a screen reader announces it once rather than twice.
 */
@Composable
private fun RoleOption(selected: Boolean, label: String, onSelect: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .selectable(selected = selected, onClick = onSelect, role = Role.RadioButton)
            .padding(vertical = 8.dp),
    ) {
        RadioButton(selected = selected, onClick = null)
        Spacer(Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.bodyLarge)
    }
}

@Preview(showBackground = true)
@Composable
private fun AuthPreview() {
    FishersTheme { AuthScreen(SessionState(isStarting = false), { _, _ -> }, { _, _, _, _ -> }) }
}
