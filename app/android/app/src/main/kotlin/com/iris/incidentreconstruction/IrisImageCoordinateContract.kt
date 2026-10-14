package com.iris.incidentreconstruction

import android.graphics.Bitmap
import androidx.exifinterface.media.ExifInterface
import java.io.File
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Native half of the versioned IRIS pixel-edge coordinate contract.
 *
 * The managed original is never changed. [oriented] maps all eight EXIF
 * orientations into the display-oriented raster used by local inference.
 * Exact resize and placement values are returned to Dart so masks, detector
 * boxes and depth samples can be related without guessing their letterboxes.
 */
object IrisImageCoordinateContract {
    const val VERSION = "iris-image-coordinate-v2"

    enum class Rounding { FLOOR, NEAREST }

    data class OrientedImage(
        val bitmap: Bitmap,
        val rawWidth: Int,
        val rawHeight: Int,
        val exifOrientation: Int,
    )

    data class Placement(
        val canvasWidth: Int,
        val canvasHeight: Int,
        val resizedWidth: Int,
        val resizedHeight: Int,
        val offsetX: Int,
        val offsetY: Int,
    )

    fun orient(bitmap: Bitmap, file: File): OrientedImage {
        val reportedOrientation = try {
            ExifInterface(file).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Throwable) {
            ExifInterface.ORIENTATION_NORMAL
        }
        // Some valid images contain ORIENTATION_UNDEFINED (0). Pixel handling
        // already treats that as unrotated; v2 metadata must record the same
        // interpretation using the contract's valid normal value (1).
        val orientation = normalizeExifOrientation(reportedOrientation)
        val oriented = orient(bitmap, orientation)
        return OrientedImage(
            oriented,
            bitmap.width,
            bitmap.height,
            orientation,
        )
    }

    internal fun normalizeExifOrientation(value: Int): Int =
        if (value in ExifInterface.ORIENTATION_NORMAL..ExifInterface.ORIENTATION_ROTATE_270) {
            value
        } else {
            ExifInterface.ORIENTATION_NORMAL
        }

    internal fun orient(bitmap: Bitmap, orientation: Int): Bitmap {
        if (orientation !in setOf(
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL,
                ExifInterface.ORIENTATION_ROTATE_180,
                ExifInterface.ORIENTATION_FLIP_VERTICAL,
                ExifInterface.ORIENTATION_TRANSPOSE,
                ExifInterface.ORIENTATION_ROTATE_90,
                ExifInterface.ORIENTATION_TRANSVERSE,
                ExifInterface.ORIENTATION_ROTATE_270,
            )
        ) {
            return bitmap
        }

        val sourceWidth = bitmap.width
        val sourceHeight = bitmap.height
        val swapsDimensions = orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
            orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
            orientation == ExifInterface.ORIENTATION_TRANSVERSE ||
            orientation == ExifInterface.ORIENTATION_ROTATE_270
        val destinationWidth = if (swapsDimensions) sourceHeight else sourceWidth
        val destinationHeight = if (swapsDimensions) sourceWidth else sourceHeight
        val sourcePixels = IntArray(sourceWidth * sourceHeight)
        val destinationPixels = IntArray(destinationWidth * destinationHeight)
        bitmap.getPixels(sourcePixels, 0, sourceWidth, 0, 0, sourceWidth, sourceHeight)

        for (sourceY in 0 until sourceHeight) {
            for (sourceX in 0 until sourceWidth) {
                val (destinationX, destinationY) = when (orientation) {
                    // EXIF orientation mappings expressed directly as source pixel
                    // coordinates to avoid Matrix pre/post-concatenation ambiguity.
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> Pair(sourceWidth - 1 - sourceX, sourceY)
                    ExifInterface.ORIENTATION_ROTATE_180 -> Pair(sourceWidth - 1 - sourceX, sourceHeight - 1 - sourceY)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> Pair(sourceX, sourceHeight - 1 - sourceY)
                    ExifInterface.ORIENTATION_TRANSPOSE -> Pair(sourceY, sourceX)
                    ExifInterface.ORIENTATION_ROTATE_90 -> Pair(sourceHeight - 1 - sourceY, sourceX)
                    ExifInterface.ORIENTATION_TRANSVERSE -> Pair(sourceHeight - 1 - sourceY, sourceWidth - 1 - sourceX)
                    ExifInterface.ORIENTATION_ROTATE_270 -> Pair(sourceY, sourceWidth - 1 - sourceX)
                    else -> error("Checked orientation was unexpectedly unsupported")
                }
                destinationPixels[destinationY * destinationWidth + destinationX] =
                    sourcePixels[sourceY * sourceWidth + sourceX]
            }
        }
        return Bitmap.createBitmap(
            destinationPixels,
            destinationWidth,
            destinationHeight,
            Bitmap.Config.ARGB_8888,
        )
    }

    fun contain(
        width: Int,
        height: Int,
        canvasWidth: Int,
        canvasHeight: Int,
        rounding: Rounding,
    ): Placement {
        require(width > 0 && height > 0 && canvasWidth > 0 && canvasHeight > 0)
        val scale = min(canvasWidth.toDouble() / width, canvasHeight.toDouble() / height)
        fun rounded(value: Double): Int = when (rounding) {
            Rounding.FLOOR -> floor(value).toInt()
            Rounding.NEAREST -> value.roundToInt()
        }.coerceAtLeast(1)
        val resizedWidth = rounded(width * scale)
        val resizedHeight = rounded(height * scale)
        return Placement(
            canvasWidth,
            canvasHeight,
            resizedWidth,
            resizedHeight,
            (canvasWidth - resizedWidth) / 2,
            (canvasHeight - resizedHeight) / 2,
        )
    }

    fun metadata(image: OrientedImage, placement: Placement): Map<String, Any> = mapOf(
        "contractVersion" to VERSION,
        "rawWidth" to image.rawWidth,
        "rawHeight" to image.rawHeight,
        "exifOrientation" to image.exifOrientation,
        "orientedWidth" to image.bitmap.width,
        "orientedHeight" to image.bitmap.height,
        "canvasWidth" to placement.canvasWidth,
        "canvasHeight" to placement.canvasHeight,
        "resizeMode" to "containLetterbox",
        "resizedWidth" to placement.resizedWidth,
        "resizedHeight" to placement.resizedHeight,
        "offsetX" to placement.offsetX,
        "offsetY" to placement.offsetY,
    )
}
