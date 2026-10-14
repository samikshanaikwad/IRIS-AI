package com.iris.incidentreconstruction

import android.graphics.Bitmap
import android.graphics.Color
import androidx.exifinterface.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class IrisImageCoordinateContractTest {
    private val a = Color.rgb(255, 0, 0)
    private val b = Color.rgb(0, 255, 0)
    private val c = Color.rgb(0, 0, 255)
    private val d = Color.rgb(255, 255, 0)
    private val e = Color.rgb(255, 0, 255)
    private val f = Color.rgb(0, 255, 255)

    @Test
    fun allExifOrientationsProduceExpectedPixels() {
        val expectations = mapOf(
            ExifInterface.ORIENTATION_NORMAL to Expected(3, 2, intArrayOf(a, b, c, d, e, f)),
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL to Expected(3, 2, intArrayOf(c, b, a, f, e, d)),
            ExifInterface.ORIENTATION_ROTATE_180 to Expected(3, 2, intArrayOf(f, e, d, c, b, a)),
            ExifInterface.ORIENTATION_FLIP_VERTICAL to Expected(3, 2, intArrayOf(d, e, f, a, b, c)),
            ExifInterface.ORIENTATION_TRANSPOSE to Expected(2, 3, intArrayOf(a, d, b, e, c, f)),
            ExifInterface.ORIENTATION_ROTATE_90 to Expected(2, 3, intArrayOf(d, a, e, b, f, c)),
            ExifInterface.ORIENTATION_TRANSVERSE to Expected(2, 3, intArrayOf(f, c, e, b, d, a)),
            ExifInterface.ORIENTATION_ROTATE_270 to Expected(2, 3, intArrayOf(c, f, b, e, a, d)),
        )
        expectations.forEach { (orientation, expected) ->
            val source = Bitmap.createBitmap(intArrayOf(a, b, c, d, e, f), 3, 2, Bitmap.Config.ARGB_8888)
            val output = IrisImageCoordinateContract.orient(source, orientation)
            assertEquals("width orientation=$orientation", expected.width, output.width)
            assertEquals("height orientation=$orientation", expected.height, output.height)
            val pixels = IntArray(output.width * output.height)
            output.getPixels(pixels, 0, output.width, 0, 0, output.width, output.height)
            assertArrayEquals("pixels orientation=$orientation", expected.pixels, pixels)
            if (output !== source) output.recycle()
            source.recycle()
        }
    }

    private data class Expected(val width: Int, val height: Int, val pixels: IntArray)
}
