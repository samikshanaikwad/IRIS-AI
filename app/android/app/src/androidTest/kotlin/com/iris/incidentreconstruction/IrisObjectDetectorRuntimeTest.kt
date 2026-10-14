package com.iris.incidentreconstruction

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class IrisObjectDetectorRuntimeTest {
    @Test
    fun detectorBoxIsIntersectedWithNormalizedCanvas() {
        assertEquals(
            listOf(0.2f, 0f, 0.8f, 1f),
            IrisObjectDetectorRuntime.clipNormalizedBox(
                floatArrayOf(0.2f, -0.001f, 0.8f, 1.002f),
            ),
        )
    }

    @Test
    fun nonFiniteOrEmptyClippedBoxIsRejected() {
        assertNull(
            IrisObjectDetectorRuntime.clipNormalizedBox(
                floatArrayOf(Float.NaN, 0f, 1f, 1f),
            ),
        )
        assertNull(
            IrisObjectDetectorRuntime.clipNormalizedBox(
                floatArrayOf(0.2f, -1f, 0.8f, -0.5f),
            ),
        )
    }
}
