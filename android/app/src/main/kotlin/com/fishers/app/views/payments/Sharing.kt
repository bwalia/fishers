package com.fishers.app.views.payments

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.fishers.app.i18n.t
import com.fishers.app.payments.PayGuideMemory
import com.fishers.app.payments.ScreenshotSize
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/** WhatsApp, then WhatsApp Business: whichever the secretary has. */
private val WHATSAPP_PACKAGES = listOf("com.whatsapp", "com.whatsapp.w4b")

/**
 * Post [text] to WhatsApp, where the club's group is — straight into its
 * "send to" list when it is installed, the phone's share sheet when it is not.
 *
 * Started rather than looked up first: Android 11 hides other apps from a
 * lookup unless the manifest names them, but never from being started, so a
 * failed start is the honest "not installed".
 */
internal fun shareToWhatsApp(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    for (pkg in WHATSAPP_PACKAGES) {
        try {
            context.startActivity(Intent(send).setPackage(pkg))
            return
        } catch (_: ActivityNotFoundException) {
            // Not this one: try the next, then the share sheet.
        }
    }
    shareAnywhere(context, text)
}

/** The phone's share sheet: a message, an email, WhatsApp — the person picks. */
internal fun shareAnywhere(context: Context, text: String, title: String = t("pa2.share_with")) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    runCatching { context.startActivity(Intent.createChooser(send, title)) }
}

/** "First time? Here's how", remembered on this phone. */
internal fun payGuidePrefs(context: Context): PayGuideMemory {
    val prefs = context.getSharedPreferences("fishers.payments", Context.MODE_PRIVATE)
    return object : PayGuideMemory {
        override fun seen() = prefs.getBoolean("pay_guide_seen", false)
        override fun markSeen() = prefs.edit().putBoolean("pay_guide_seen", true).apply()
    }
}

/**
 * The system photo picker for a picture of a payment, shrunk on the phone to
 * what the server keeps: at most 1600 px and under a megabyte. No storage
 * permission is needed. [onProblem] gets a sentence for a picture that cannot
 * be read, or is too big even shrunk.
 */
@Composable
internal fun rememberScreenshotPicker(onReady: (ByteArray) -> Unit, onProblem: (String) -> Unit): () -> Unit {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            when (val result = withContext(Dispatchers.IO) { prepareScreenshot(context, uri) }) {
                is Prepared.Ready -> onReady(result.bytes)
                Prepared.Unreadable -> onProblem(t("pa2.screenshot_unreadable"))
                Prepared.TooBig -> onProblem(t("pa2.screenshot_too_big"))
            }
        }
    }
    return { launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
}

private sealed interface Prepared {
    class Ready(val bytes: ByteArray) : Prepared
    data object Unreadable : Prepared
    data object TooBig : Prepared
}

/**
 * A JPEG of the picture, the right way up, small enough to send — decoded at
 * a fraction of full size first, so a big photo never takes the app's memory.
 */
private fun prepareScreenshot(context: Context, uri: Uri): Prepared {
    val decoded = runCatching {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "not an image" }
        val sample = ScreenshotSize.sampleSize(bounds.outWidth, bounds.outHeight)
        val bitmap = checkNotNull(
            resolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            },
        ) { "could not decode" }
        val rotation = resolver.openInputStream(uri)?.use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } ?: 0f
        bitmap to rotation
    }.getOrNull() ?: return Prepared.Unreadable
    val (bitmap, rotation) = decoded
    val bytes = runCatching { ScreenshotSize.shrink { maxSide, quality ->
        val (w, h) = ScreenshotSize.fit(bitmap.width, bitmap.height, maxSide)
        val matrix = Matrix().apply {
            postScale(w.toFloat() / bitmap.width, h.toFloat() / bitmap.height)
            if (rotation != 0f) postRotate(rotation)
        }
        val shaped = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        ByteArrayOutputStream().use { out ->
            shaped.compress(Bitmap.CompressFormat.JPEG, quality, out)
            if (shaped !== bitmap) shaped.recycle()
            out.toByteArray()
        }
    } }.getOrNull()
    bitmap.recycle()
    return bytes?.let { Prepared.Ready(it) } ?: Prepared.TooBig
}
