package com.iris.incidentreconstruction

import android.graphics.BitmapFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.calib3d.Calib3d
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfDMatch
import org.opencv.core.MatOfKeyPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.features2d.BFMatcher
import org.opencv.features2d.ORB
import org.opencv.imgproc.Imgproc

class IrisMultiViewRuntime {
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "analyzePair") return false
        try {
            val args = call.arguments as? Map<*, *> ?: error("Pair arguments are required.")
            val pathA = args["pathA"] as? String ?: error("Image A path is required.")
            val pathB = args["pathB"] as? String ?: error("Image B path is required.")
            result.success(analyze(pathA, pathB))
        } catch (error: Throwable) {
            result.success(mapOf("status" to "ERROR", "message" to (error.message ?: "OpenCV analysis failed.")))
        }
        return true
    }

    private fun analyze(pathA: String, pathB: String): Map<String, Any> {
        check(OpenCVLoader.initLocal()) { "OpenCV could not initialize." }
        val a = loadGray(pathA)
        val b = loadGray(pathB)
        val orb = ORB.create(800)
        val ka = MatOfKeyPoint(); val kb = MatOfKeyPoint()
        val da = Mat(); val db = Mat()
        orb.detectAndCompute(a, Mat(), ka, da)
        orb.detectAndCompute(b, Mat(), kb, db)
        val base = mutableMapOf<String, Any>(
            "imageWidthA" to a.cols(), "imageHeightA" to a.rows(), "imageWidthB" to b.cols(), "imageHeightB" to b.rows(),
            "featureCountA" to ka.toArray().size,
            "featureCountB" to kb.toArray().size,
            "candidateMatchCount" to 0,
            "acceptedMatchCount" to 0,
            "verifiedInlierCount" to 0,
            "inlierRatio" to 0.0,
            "geometricModel" to "fundamental_matrix_ransac",
            "correspondences" to emptyList<List<Double>>(),
        )
        if (da.empty() || db.empty() || ka.empty() || kb.empty()) {
            base["status"] = "INSUFFICIENT_FEATURES"; return base
        }
        val knn = mutableListOf<MatOfDMatch>()
        BFMatcher.create(Core.NORM_HAMMING).knnMatch(da, db, knn, 2)
        val accepted = knn.mapNotNull { pair ->
            val m = pair.toArray()
            if (m.size >= 2 && m[0].distance < 0.75f * m[1].distance) m[0] else null
        }
        base["candidateMatchCount"] = knn.size
        base["acceptedMatchCount"] = accepted.size
        if (accepted.size < 8) { base["status"] = "INSUFFICIENT_MATCHES"; return base }
        val pointsA = accepted.map { ka.toArray()[it.queryIdx].pt }
        val pointsB = accepted.map { kb.toArray()[it.trainIdx].pt }
        val mask = Mat()
        val fundamental = Calib3d.findFundamentalMat(
            MatOfPoint2f(*pointsA.toTypedArray()), MatOfPoint2f(*pointsB.toTypedArray()),
            Calib3d.FM_RANSAC, 3.0, 0.99, mask,
        )
        if (fundamental.empty() || mask.empty()) { base["status"] = "GEOMETRIC_VERIFICATION_FAILED"; return base }
        val inlierFlags = ByteArray(mask.total().toInt()); mask.get(0, 0, inlierFlags)
        val inliers = mutableListOf<List<Double>>()
        for (i in inlierFlags.indices) if (inlierFlags[i].toInt() != 0) {
            inliers += listOf(pointsA[i].x, pointsA[i].y, pointsB[i].x, pointsB[i].y)
        }
        val ratio = inliers.size.toDouble() / accepted.size.toDouble()
        base["verifiedInlierCount"] = inliers.size
        base["inlierRatio"] = ratio
        base["correspondences"] = inliers.take(40)
        base["status"] = if (inliers.size >= 8 && ratio >= 0.25) "VERIFIED_CORRESPONDENCE" else "GEOMETRIC_VERIFICATION_FAILED"
        return base
    }

    private fun loadGray(path: String): Mat {
        val bitmap = BitmapFactory.decodeFile(path) ?: error("Evidence image could not be decoded.")
        val scale = minOf(1.0, 640.0 / maxOf(bitmap.width, bitmap.height).toDouble())
        val resized = if (scale < 1.0) android.graphics.Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
        val rgba = Mat(); Utils.bitmapToMat(resized, rgba)
        val gray = Mat(); Imgproc.cvtColor(rgba, gray, Imgproc.COLOR_RGBA2GRAY)
        return gray
    }
}
