package com.fishers.app.views.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fishers.app.R
import com.fishers.app.i18n.t
import com.fishers.app.profile.SportProfile
import com.fishers.app.profile.labelOf

/**
 * The band across the top of a player's page — `ProfileHeroView.swift`.
 *
 * Laid out the way a cricket profile is read rather than the way the record is
 * stored: the photo, the name set as a scorecard sets it — given name light,
 * family name heavy and upper — then the club, the standard and the position.
 * [onPickPhoto] is null on somebody else's page, where there is no camera.
 */
@Composable
internal fun ProfileHero(
    name: String,
    avatarUrl: String?,
    club: String?,
    main: SportProfile?,
    photoBusy: Boolean = false,
    photoError: String? = null,
    avatarSize: Dp = 96.dp,
    onPickPhoto: (() -> Unit)? = null,
) {
    val deep = colorResource(R.color.brand_primary_900)
    val mid = colorResource(R.color.brand_primary_700)
    val accent = colorResource(R.color.brand_accent_400)
    val (first, last) = splitName(name)

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Brush.linearGradient(listOf(deep, mid)))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box {
                Avatar(name, avatarUrl, avatarSize, Modifier.border(3.dp, accent, CircleShape))
                if (onPickPhoto != null) {
                    // The visual circle is small; the tap target is not.
                    IconButton(
                        onClick = onPickPhoto,
                        enabled = !photoBusy,
                        modifier = Modifier.align(Alignment.BottomEnd).offset(x = 8.dp, y = 8.dp),
                    ) {
                        Box(Modifier.size(32.dp).clip(CircleShape).background(accent), Alignment.Center) {
                            if (photoBusy) {
                                CircularProgressIndicator(Modifier.size(16.dp), color = deep, strokeWidth = 2.dp)
                            } else {
                                Icon(
                                    Icons.Filled.PhotoCamera,
                                    contentDescription = if (avatarUrl == null) t("ld.add_a_photo") else t("ld.change_your_photo"),
                                    tint = deep,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                if (first.isNotEmpty()) {
                    Text(first, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Light,
                        color = Color.White.copy(alpha = 0.86f))
                }
                Text(
                    last.uppercase(),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        val level = main?.tier?.label ?: main?.skillLevel
        val position = main?.position?.takeIf { it.isNotBlank() }
            ?.let { main.sportKind?.positions?.labelOf(it) ?: it }
        if (club != null || level != null || position != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val line = listOfNotNull(club, level).joinToString("  ·  ")
                if (line.isNotEmpty()) {
                    Text(line, style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.82f),
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                }
                position?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.labelLarge,
                        color = Color.White,
                        maxLines = 1,
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(accent.copy(alpha = 0.25f))
                            .border(1.dp, accent.copy(alpha = 0.55f), RoundedCornerShape(50))
                            .padding(horizontal = 12.dp, vertical = 4.dp),
                    )
                }
            }
        }

        photoError?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Color.White) }
    }
}
