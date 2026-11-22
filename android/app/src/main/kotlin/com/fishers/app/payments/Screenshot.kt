package com.fishers.app.payments

import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Making a picture of a payment small enough to send.
 *
 * The server keeps at most a megabyte (`MAX_SCREENSHOT_BYTES` in
 * `easy_paying.rs`) and asks the phone to shrink first: at most 1600 px on the
 * long edge, JPEG at quality 0.7. A banking app's screenshot is well under
 * that; a camera photo of a receipt is not, so it steps down — lower quality,
 * then fewer pixels — until it fits. The decoding and encoding are Android's
 * and live with the picker; what is decided here is plain arithmetic.
 */
object ScreenshotSize {
    /** The server's limit, less a little so a rounding never tips it over. */
    const val MAX_BYTES = 1_000_000 - 8 * 1024

    const val MAX_SIDE = 1600

    /** Tried in order: the size and quality the plan asks for first. */
    val ATTEMPTS: List<Pair<Int, Int>> = listOf(
        MAX_SIDE to 70,
        MAX_SIDE to 55,
        1280 to 55,
        1024 to 50,
        800 to 45,
    )

    /** [width] × [height] scaled to fit within [maxSide] on the long edge; never enlarged. */
    fun fit(width: Int, height: Int, maxSide: Int = MAX_SIDE): Pair<Int, Int> {
        require(width > 0 && height > 0) { "not an image" }
        val long = max(width, height)
        if (long <= maxSide) return width to height
        val scale = maxSide.toDouble() / long
        return (width * scale).roundToInt().coerceAtLeast(1) to (height * scale).roundToInt().coerceAtLeast(1)
    }

    /**
     * The power-of-two `inSampleSize` that decodes no smaller than [maxSide]:
     * a 50-megapixel photo is never held at full size just to be shrunk.
     */
    fun sampleSize(width: Int, height: Int, maxSide: Int = MAX_SIDE): Int {
        var sample = 1
        while (max(width, height) / (sample * 2) >= maxSide) sample *= 2
        return sample
    }

    /**
     * The first encoding that fits, trying each of [ATTEMPTS]: [encode] is
     * handed a long edge and a JPEG quality. Null when even the smallest is
     * too big, which a real screenshot never is.
     */
    fun shrink(encode: (maxSide: Int, quality: Int) -> ByteArray): ByteArray? {
        for ((side, quality) in ATTEMPTS) {
            val bytes = encode(side, quality)
            if (bytes.isNotEmpty() && bytes.size <= MAX_BYTES) return bytes
        }
        return null
    }
}
