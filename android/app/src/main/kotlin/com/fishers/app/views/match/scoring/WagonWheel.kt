@file:OptIn(ExperimentalMaterial3Api::class)

package com.fishers.app.views.match.scoring

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fishers.app.cricket.InningsView
import com.fishers.app.cricket.MatchView
import com.fishers.app.cricket.Shot
import com.fishers.app.cricket.Shots
import com.fishers.app.cricket.WheelMode
import com.fishers.app.i18n.t
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sin

/** The scorer's choice of how often to be asked, kept on this phone like iOS's `@AppStorage`. */
internal object WheelSetting {
    private const val PREFS = "fishers.scoring"
    private const val KEY = "cricket_wheel_mode"

    fun read(context: Context): WheelMode =
        WheelMode.of(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null))

    fun write(context: Context, mode: WheelMode) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, mode.wire).apply()
    }
}

/** Where on the field a point is, as the engine records it: 0° straight down the ground, clockwise. */
private fun angleOf(dx: Float, dy: Float): Int =
    ((atan2(dx.toDouble(), -dy.toDouble()) * 180 / PI + 360) % 360).roundToInt() % 360

private fun pointAt(centre: Offset, radius: Float, degrees: Int): Offset {
    val radians = (degrees - 90) * PI / 180
    return Offset(centre.x + radius * cos(radians).toFloat(), centre.y + radius * sin(radians).toFloat())
}

/** The field from the batter's end: the bowler at the top, the rope at the edge, the ring and the pitch. */
private fun DrawScope.field(grass: Color, line: Color, pitch: Color) {
    val radius = size.minDimension / 2
    val centre = Offset(size.width / 2, size.height / 2)
    drawCircle(grass, radius, centre)
    drawCircle(line, radius, centre, style = Stroke(width = 3f))
    drawCircle(
        line.copy(alpha = 0.5f),
        radius * 0.55f,
        centre,
        style = Stroke(width = 2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f))),
    )
    val pitchSize = Size(radius * 0.14f, radius * 0.56f)
    drawRect(pitch, Offset(centre.x - pitchSize.width / 2, centre.y - pitchSize.height / 2), pitchSize)
}

/**
 * "Where did the ball go?" — one tap on the field, a stroke, and save. Asked
 * before the ball is written, so the shot rides on the same event and an undo
 * takes both away together. Skipping is always one tap.
 */
@Composable
internal fun WheelPicker(
    batterName: String,
    batsLeft: Boolean,
    runs: Int,
    onSave: (Shot) -> Unit,
    onSkip: () -> Unit,
    onCancel: () -> Unit,
) {
    var angle by remember { mutableStateOf<Int?>(null) }
    var reach by remember { mutableFloatStateOf(0.8f) }
    var kind by remember { mutableStateOf(Shots.likely(runs).first()) }
    val colour = when (runs) {
        6 -> BallColours.six
        4 -> BallColours.four
        else -> MaterialTheme.colorScheme.primary
    }
    val grass = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
    val line = MaterialTheme.colorScheme.primary.copy(alpha = 0.45f)
    val pitch = BallColours.extra.copy(alpha = 0.3f)

    // Swiped away is "not that ball", as on iOS: only Skip or Save writes it.
    ModalBottomSheet(onDismissRequest = onCancel, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(t("sc.where_did_it_go"), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(
                "$batterName — ${t("la.over_runs", count = runs, vars = mapOf("n" to runs))}",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            fun place(at: Offset, width: Float, height: Float) {
                val dx = at.x - width / 2
                val dy = at.y - height / 2
                val distance = hypot(dx, dy)
                if (distance < 6f) return
                angle = angleOf(dx, dy)
                // A boundary always reaches the rope.
                reach = if (runs >= 4) 1f else (distance / (minOf(width, height) / 2)).coerceIn(0.15f, 1f)
            }
            Canvas(
                Modifier
                    .widthIn(max = 340.dp)
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .semantics { contentDescription = t("sc.wagon_wheel_tap") }
                    .pointerInput(runs) {
                        detectTapGestures { place(it, size.width.toFloat(), size.height.toFloat()) }
                    }
                    .pointerInput(runs) {
                        detectDragGestures { change, _ -> place(change.position, size.width.toFloat(), size.height.toFloat()) }
                    },
            ) {
                field(grass, line, pitch)
                val radius = size.minDimension / 2
                val centre = Offset(size.width / 2, size.height / 2)
                angle?.let { a ->
                    val end = pointAt(centre, radius * reach, a)
                    drawLine(colour, centre, end, strokeWidth = 8f, cap = StrokeCap.Round)
                    drawCircle(colour, 12f, end)
                }
            }
            Text(
                angle?.let { "${Shots.label(kind)} — ${Shots.region(it, batsLeft)}" } ?: t("sc.tap_where_it_went"),
                style = MaterialTheme.typography.titleMedium,
                color = if (angle == null) MaterialTheme.colorScheme.onSurfaceVariant else colour,
            )
            WordChoice(Shots.ordered(runs).map { it to Shots.label(it) }, kind) { kind = it }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(onClick = onSkip, modifier = Modifier.weight(1f).heightIn(min = 56.dp)) {
                    Text(t("sc.skip_just_the_runs"))
                }
                Button(
                    onClick = { angle?.let { onSave(Shot(it, kind, reach)) } },
                    enabled = angle != null,
                    modifier = Modifier.weight(1f).heightIn(min = 56.dp),
                ) { Text(t("lc.save")) }
            }
        }
    }
}

/** Every shot the scorer plotted in an innings, or one batter's — the card's wagon wheel. */
@Composable
internal fun WheelChart(view: MatchView, inn: InningsView) {
    var batter by rememberSaveable(inn.index) { mutableStateOf<String?>(null) }
    val shots = inn.deliveries.filter { it.shot != null && (batter == null || it.batterId == batter) }
    val grass = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
    val line = MaterialTheme.colorScheme.primary.copy(alpha = 0.45f)
    val pitch = BallColours.extra.copy(alpha = 0.3f)
    val other = MaterialTheme.colorScheme.primary
    val boundaries = shots.count { it.label == "4" || it.label == "6" }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        WordChoice(
            listOf<String?>(null).plus(inn.batted.map { it.playerId }).map { it to (it?.let(view::name) ?: t("sc.whole_innings")) },
            batter,
        ) { batter = it }
        Canvas(
            Modifier
                .widthIn(max = 360.dp)
                .fillMaxWidth()
                .aspectRatio(1f)
                .semantics {
                    contentDescription = t("wheel.aria", vars = mapOf("shots" to shots.size, "boundaries" to boundaries))
                },
        ) {
            field(grass, line, pitch)
            val radius = size.minDimension / 2
            val centre = Offset(size.width / 2, size.height / 2)
            shots.forEach { ball ->
                val shot = ball.shot ?: return@forEach
                val colour = when (ball.label) {
                    "6" -> BallColours.six
                    "4" -> BallColours.four
                    else -> other
                }
                drawLine(colour, centre, pointAt(centre, radius * shot.reach.coerceIn(0.1f, 1f), shot.angle), strokeWidth = 5f, cap = StrokeCap.Round)
            }
        }
        Text(
            if (shots.isEmpty()) t("sc.no_shots_recorded_yet") else t("wheel.plotted", count = shots.size, vars = mapOf("count" to shots.size)),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(t("sc.shots_the_scorer_plotted"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
