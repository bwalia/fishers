package com.fishers.app.views.onboarding

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.fishers.app.R
import com.fishers.app.i18n.t
import kotlinx.coroutines.delay

/**
 * A player sends their profile to a club secretary, who invites them in —
 * `ShareProfileView.swift`.
 *
 * One link, sent however the two of them actually talk. Most clubs run on a
 * WhatsApp group, so that has its own button; the share sheet covers the rest.
 * The secretary sees a card with no contact details and sends an invite; the
 * player still has to accept it.
 */
@Composable
fun ShareProfileCard(
    link: String?,
    busy: Boolean,
    error: String?,
    onGetLink: () -> Unit,
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val brand = stringResource(R.string.brand_name)
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2_000)
            copied = false
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (link == null) {
            Button(onClick = onGetLink, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Filled.Link, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(t("le.get_my_profile_link"))
                }
            }
        } else {
            val message = t("fin.share_profile_message", vars = mapOf("brand" to brand, "url" to link))
            SelectionContainer {
                Text(link, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 2)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        clipboard.setText(AnnotatedString(link))
                        copied = true
                    },
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                ) {
                    Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text(if (copied) t("le.copied") else t("cl.copy"))
                }
                Button(
                    onClick = {
                        val send = Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_TEXT, message)
                        context.startActivity(Intent.createChooser(send, null))
                    },
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                ) {
                    Icon(Icons.Filled.Share, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text(t("sc.share"))
                }
            }
            OutlinedButton(
                onClick = {
                    val whatsapp = Uri.parse("https://wa.me/").buildUpon().appendQueryParameter("text", message).build()
                    // wa.me opens WhatsApp where it is installed and the
                    // website where it is not, so there is always somewhere to go.
                    try {
                        context.startActivity(Intent(Intent.ACTION_VIEW, whatsapp))
                    } catch (_: ActivityNotFoundException) {
                        context.startActivity(
                            Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, message), null),
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) { Text(t("fin.send_on_whatsapp")) }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
    }
}
