package com.iris.incidentreconstruction

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import androidx.exifinterface.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.exp
import kotlin.math.min

/** App-owned offline V0 TFLite executor. No classification is synthesized. */
class IrisClassifierRuntime(private val context: Context) : AutoCloseable {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var interpreter: Interpreter? = null

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method == "smoke") {
            executor.execute {
                try {
                    val runtime = getInterpreter()
                    mainHandler.post {
                        result.success(mapOf(
                            "modelSha256" to modelSha256,
                            "inputShape" to runtime.getInputTensor(0).shape().toList(),
                            "outputShape" to runtime.getOutputTensor(0).shape().toList(),
                        ))
                    }
                } catch (error: Throwable) {
                    mainHandler.post {
                        result.error("classifier_failure", "Local classifier runtime is unavailable.", error.javaClass.name)
                    }
                }
            }
            return true
        }
        if (call.method != "run") return false
        val path = call.argument<String>("absolutePath")
        if (path.isNullOrBlank()) {
            result.error("invalid_argument", "A managed evidence path is required.", null)
            return true
        }
        executor.execute {
            try {
                val logit = run(File(path))
                mainHandler.post {
                    result.success(mapOf("rawLogit" to logit, "modelSha256" to modelSha256))
                }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("classifier_failure", "Local image classification could not be completed.", error.javaClass.name)
                }
            }
        }
        return true
    }

    @Synchronized
    private fun getInterpreter(): Interpreter {
        interpreter?.let { return it }
        val model = context.assets.open(modelAsset).use { stream ->
            val bytes = stream.readBytes()
            check(sha256(bytes) == modelSha256) { "Bundled V0 classifier hash mismatch." }
            ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply {
                put(bytes)
                rewind()
            }
        }
        return Interpreter(model, Interpreter.Options().setNumThreads(2)).also { interpreter = it }
    }

    private fun run(file: File): Float {
        check(file.isFile) { "Managed evidence file is unavailable." }
        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
            ?: throw IllegalArgumentException("Managed evidence could not be decoded.")
        val oriented = applyExifOrientation(bitmap, file)
        if (oriented !== bitmap) bitmap.recycle()
        try {
            val input = preprocess(oriented)
            val output = Array(1) { FloatArray(1) }
            val runtime = getInterpreter()
            check(runtime.getInputTensor(0).shape().contentEquals(intArrayOf(1, 224, 224, 3))) {
                "Unexpected V0 classifier input tensor contract."
            }
            check(runtime.getOutputTensor(0).shape().contentEquals(intArrayOf(1, 1))) {
                "Unexpected V0 classifier output tensor contract."
            }
            runtime.run(input, output)
            val logit = output[0][0]
            check(logit.isFinite()) { "Classifier returned a non-finite logit." }
            return logit
        } finally {
            oriented.recycle()
        }
    }

    private fun preprocess(source: Bitmap): ByteBuffer {
        val scale = min(224.0 / source.width, 224.0 / source.height)
        val width = (source.width * scale).toInt().coerceAtLeast(1)
        val height = (source.height * scale).toInt().coerceAtLeast(1)
        val resized = Bitmap.createScaledBitmap(source, width, height, true)
        val canvas = Bitmap.createBitmap(224, 224, Bitmap.Config.ARGB_8888)
        Canvas(canvas).apply {
            drawColor(android.graphics.Color.BLACK)
            drawBitmap(resized, ((224 - width) / 2).toFloat(), ((224 - height) / 2).toFloat(), Paint(Paint.FILTER_BITMAP_FLAG))
        }
        resized.recycle()
        val input = ByteBuffer.allocateDirect(4 * 224 * 224 * 3).order(ByteOrder.nativeOrder())
        val pixels = IntArray(224 * 224)
        canvas.getPixels(pixels, 0, 224, 0, 0, 224, 224)
        for (pixel in pixels) {
            input.putFloat((((pixel shr 16) and 0xff) / 255.0f - mean[0]) / standardDeviation[0])
            input.putFloat((((pixel shr 8) and 0xff) / 255.0f - mean[1]) / standardDeviation[1])
            input.putFloat(((pixel and 0xff) / 255.0f - mean[2]) / standardDeviation[2])
        }
        canvas.recycle()
        input.rewind()
        return input
    }

    private fun applyExifOrientation(bitmap: Bitmap, file: File): Bitmap {
        val orientation = try { ExifInterface(file).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) } catch (_: Throwable) { ExifInterface.ORIENTATION_NORMAL }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.preScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.preScale(-1f, 1f) }
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    override fun close() {
        executor.shutdown()
        synchronized(this) { interpreter?.close(); interpreter = null }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    companion object {
        const val modelAsset = "models/iris_v0_experimental_mobilenet_v3_small.tflite"
        const val modelSha256 = "e98d17518b0296a484a0a94c21359a6703b11b56e5db53a1cc659b8b3a440c96"
        private val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
        private val standardDeviation = floatArrayOf(0.229f, 0.224f, 0.225f)
        private val mainHandler = Handler(Looper.getMainLooper())
    }
}
