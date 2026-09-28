package com.iris.incidentreconstruction

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.calib3d.Calib3d
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfDMatch
import org.opencv.core.CvType
import org.opencv.core.MatOfKeyPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.features2d.BFMatcher
import org.opencv.features2d.ORB
import org.opencv.imgproc.Imgproc

/** Runtime-only qualification. It does not enter the production Flutter path. */
@RunWith(AndroidJUnit4::class)
class OpenCvRuntimeSmokeTest {
    @Test
    fun opencvOrbMatchingAndFundamentalRansacExecute() {
        assertTrue("OpenCV native library failed to initialize", OpenCVLoader.initLocal())

        val first = texturedBitmap(640, 480)
        val firstMat = Mat()
        Utils.bitmapToMat(first, firstMat)
        val grayA = Mat()
        Imgproc.cvtColor(firstMat, grayA, Imgproc.COLOR_RGBA2GRAY)

        val homography = Mat(3, 3, CvType.CV_64F)
        homography.put(0, 0, *doubleArrayOf(
            1.0, 0.0, 8.0,
            0.0, 1.0, 5.0,
            0.00008, 0.00004, 1.0,
        ))
        val secondMat = Mat()
        Imgproc.warpPerspective(firstMat, secondMat, homography, Size(640.0, 480.0))
        val grayB = Mat()
        Imgproc.cvtColor(secondMat, grayB, Imgproc.COLOR_RGBA2GRAY)

        val orb = ORB.create(800)
        val keypointsA = MatOfKeyPoint()
        val keypointsB = MatOfKeyPoint()
        val descriptorsA = Mat()
        val descriptorsB = Mat()
        orb.detectAndCompute(grayA, Mat(), keypointsA, descriptorsA)
        orb.detectAndCompute(grayB, Mat(), keypointsB, descriptorsB)
        assertTrue("ORB found no keypoints in source image", keypointsA.toArray().isNotEmpty())
        assertTrue("ORB found no keypoints in transformed image", keypointsB.toArray().isNotEmpty())
        assertFalse("ORB produced no descriptors", descriptorsA.empty() || descriptorsB.empty())

        val matches = MatOfDMatch()
        BFMatcher.create(Core.NORM_HAMMING, true).match(descriptorsA, descriptorsB, matches)
        val usable = matches.toArray().filter { it.distance.isFinite() && it.distance < 80f }
        assertTrue("Binary descriptor matcher produced too few real matches", usable.size >= 8)

        val pointsA = usable.map { keypointsA.toArray()[it.queryIdx].pt }
        val pointsB = usable.map { keypointsB.toArray()[it.trainIdx].pt }
        val mask = Mat()
        val fundamental = Calib3d.findFundamentalMat(
            MatOfPoint2f(*pointsA.toTypedArray()), MatOfPoint2f(*pointsB.toTypedArray()),
            Calib3d.FM_RANSAC, 3.0, 0.99, mask,
        )
        assertFalse("Fundamental matrix estimation returned no model", fundamental.empty())
        assertTrue("RANSAC did not produce an inlier mask", mask.rows() > 0 || mask.cols() > 0)
        val inliers = Core.countNonZero(mask.reshape(1))
        assertTrue("RANSAC produced no geometrically verified inliers", inliers > 0)

        val unrelated = Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888)
        Canvas(unrelated).drawColor(Color.rgb(96, 96, 96))
        val unrelatedMat = Mat()
        Utils.bitmapToMat(unrelated, unrelatedMat)
        val unrelatedGray = Mat()
        Imgproc.cvtColor(unrelatedMat, unrelatedGray, Imgproc.COLOR_RGBA2GRAY)
        val unrelatedKeypoints = MatOfKeyPoint()
        val unrelatedDescriptors = Mat()
        orb.detectAndCompute(unrelatedGray, Mat(), unrelatedKeypoints, unrelatedDescriptors)
        if (unrelatedDescriptors.empty()) {
            assertTrue("Uniform unrelated image unexpectedly produced descriptors", true)
        } else {
            val unrelatedMatches = MatOfDMatch()
            BFMatcher.create(Core.NORM_HAMMING, true).match(descriptorsA, unrelatedDescriptors, unrelatedMatches)
            val unrelatedUsable = unrelatedMatches.toArray().count { it.distance.isFinite() && it.distance < 40f }
            assertTrue("Unrelated controlled image pair matched as a valid scene", unrelatedUsable < usable.size)
        }
    }

    private fun texturedBitmap(width: Int, height: Int, seed: Int = 11): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.rgb(18, 22, 28))
        val paint = android.graphics.Paint().apply { color = Color.WHITE; strokeWidth = 3f }
        for (i in 0 until 80) {
            val x = ((i * 83 + seed * 17) % (width - 30) + 15).toFloat()
            val y = ((i * 47 + seed * 29) % (height - 30) + 15).toFloat()
            canvas.drawCircle(x, y, 5f + (i % 4), paint)
            canvas.drawLine(x - 14, y + 11, x + 16, y - 9, paint)
        }
        return bitmap
    }
}
