package com.iris.incidentreconstruction

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.FloatBuffer
import java.security.MessageDigest
import kotlin.math.roundToInt

class IrisDepthRuntime(private val context: Context) : AutoCloseable {
    private val environment = OrtEnvironment.getEnvironment()
    private var session: OrtSession? = null
    private val modelSha256 = "f983ac210c302d37e0c07b075575426a4694a2b6eed6414fe66339bcb75a6830"

    @Synchronized
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "run") return false
        val path = call.argument<String>("absolutePath")
        if (path == null) {
            result.error("depth_input", "Evidence path is missing.", null)
            return true
        }
        Thread {
            try {
                val output = run(path)
                result.success(output)
            } catch (error: Throwable) {
                result.error("depth_failure", error.message ?: "Depth inference failed.", error.javaClass.name)
            }
        }.start()
        return true
    }

    private fun run(path: String): Map<String, Any> {
        val image = decodeOriented(File(path))
        val originalWidth = image.width
        val originalHeight = image.height
        val scale = minOf(518f / originalWidth, 518f / originalHeight)
        val resizedWidth = (originalWidth * scale).roundToInt().coerceAtLeast(1)
        val resizedHeight = (originalHeight * scale).roundToInt().coerceAtLeast(1)
        val resized = Bitmap.createScaledBitmap(image, resizedWidth, resizedHeight, true)
        val canvasBitmap = Bitmap.createBitmap(518, 518, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(canvasBitmap)
        canvas.drawColor(android.graphics.Color.rgb(124, 116, 103))
        val offsetX = (518 - resizedWidth) / 2
        val offsetY = (518 - resizedHeight) / 2
        canvas.drawBitmap(resized, offsetX.toFloat(), offsetY.toFloat(), null)
        val pixels = IntArray(518 * 518)
        canvasBitmap.getPixels(pixels, 0, 518, 0, 0, 518, 518)
        val input = FloatArray(3 * 518 * 518)
        val mean = floatArrayOf(.485f, .456f, .406f)
        val std = floatArrayOf(.229f, .224f, .225f)
        for (i in pixels.indices) {
            val pixel = pixels[i]
            val rgb = floatArrayOf(
                android.graphics.Color.red(pixel) / 255f,
                android.graphics.Color.green(pixel) / 255f,
                android.graphics.Color.blue(pixel) / 255f,
            )
            input[i] = (rgb[0] - mean[0]) / std[0]
            input[518 * 518 + i] = (rgb[1] - mean[1]) / std[1]
            input[2 * 518 * 518 + i] = (rgb[2] - mean[2]) / std[2]
        }
        val started = System.nanoTime()
        val activeSession = ensureSession()
        val tensor = OnnxTensor.createTensor(environment, FloatBuffer.wrap(input), longArrayOf(1, 3, 518, 518))
        val results = activeSession.run(mapOf("image" to tensor))
        tensor.close()
        val value = results[0].value
        results.close()
        val depth = flatten(value)
        require(depth.size == 518 * 518) { "Unexpected depth output size: ${depth.size}" }
        require(depth.all { it.isFinite() }) { "Depth output contains non-finite values." }
        require(depth.maxOrNull() != depth.minOrNull()) { "Depth output has no variation." }
        image.recycle(); resized.recycle(); canvasBitmap.recycle()
        return mapOf(
            "modelSha256" to modelSha256,
            "contractVersion" to "v1",
            "width" to originalWidth,
            "height" to originalHeight,
            "modelWidth" to 518,
            "modelHeight" to 518,
            "paddingLeft" to offsetX,
            "paddingTop" to offsetY,
            "resizedWidth" to resizedWidth,
            "resizedHeight" to resizedHeight,
            "depth" to depth,
            "inferenceMs" to ((System.nanoTime() - started) / 1_000_000L).toInt(),
        )
    }

    private fun ensureSession(): OrtSession {
        session?.let { return it }
        val model = File(context.cacheDir, "iris_v0_depth_vits_518.ort")
        if (!model.exists()) {
            context.assets.open("models/iris_v0_depth_vits_518.ort").use { input -> model.outputStream().use { input.copyTo(it) } }
        }
        require(sha256(model) == modelSha256) { "Depth model hash mismatch." }
        val options = OrtSession.SessionOptions()
        options.addConfigEntry("session.load_model_format", "ORT")
        session = environment.createSession(model.absolutePath, options)
        return session!!
    }

    private fun decodeOriented(file: File): Bitmap {
        require(file.exists()) { "Evidence file is unavailable." }
        val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: error("Evidence image could not be decoded.")
        val orientation = ExifInterface(file.absolutePath).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        val matrix = android.graphics.Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true).also { if (it != bitmap) bitmap.recycle() }
    }

    private fun flatten(value: Any?): List<Float> = when (value) {
        is FloatArray -> value.toList()
        is Array<*> -> value.flatMap { flatten(it) }
        else -> error("Unexpected depth output type: ${value?.javaClass?.name}")
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val buffer = ByteArray(1024 * 1024); while (true) { val n = input.read(buffer); if (n <= 0) break; digest.update(buffer, 0, n) } }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    override fun close() { session?.close(); session = null }
}
