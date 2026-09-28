package com.iris.incidentreconstruction

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
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
import java.util.concurrent.Executors
import kotlin.math.min

class IrisObjectDetectorRuntime(private val context: Context) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private var interpreter: Interpreter? = null

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "run") return false
        val path = call.argument<String>("absolutePath")
        if (path.isNullOrBlank()) { result.error("invalid_argument", "A managed evidence path is required.", null); return true }
        executor.execute {
            try { val output = run(File(path)); Handler(Looper.getMainLooper()).post { result.success(output) } }
            catch (e: Throwable) { Handler(Looper.getMainLooper()).post { result.error("detector_failure", "Local object detection could not be completed.", e.javaClass.name) } }
        }
        return true
    }

    @Synchronized private fun getInterpreter(): Interpreter {
        interpreter?.let { return it }
        val bytes = context.assets.open(modelAsset).use { it.readBytes() }
        check(sha256(bytes) == modelSha256) { "Bundled V0 detector hash mismatch." }
        return Interpreter(ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply { put(bytes); rewind() }, Interpreter.Options().setNumThreads(2)).also {
            check(it.getInputTensor(0).shape().contentEquals(intArrayOf(1, 320, 320, 3)))
            check(it.getInputTensor(0).dataType() == org.tensorflow.lite.DataType.UINT8)
            interpreter = it
        }
    }

    private fun run(file: File): Map<String, Any> {
        check(file.isFile) { "Managed evidence file is unavailable." }
        val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: error("Managed evidence could not be decoded.")
        val oriented = orient(bitmap, file); if (oriented !== bitmap) bitmap.recycle()
        try {
            val input = preprocess(oriented); val outputs = hashMapOf<Int, Any>(0 to Array(1) { Array(25) { FloatArray(4) } }, 1 to Array(1) { FloatArray(25) }, 2 to Array(1) { FloatArray(25) }, 3 to FloatArray(1)); val started = System.nanoTime(); getInterpreter().runForMultipleInputsOutputs(arrayOf(input), outputs); val boxes = outputs[0] as Array<Array<FloatArray>>; val classes = outputs[1] as Array<FloatArray>; val scores = outputs[2] as Array<FloatArray>; val count = (outputs[3] as FloatArray)[0].toInt().coerceIn(0, 25); val detections = mutableListOf<Map<String, Any>>(); val allowed = mapOf(0 to "person", 1 to "bicycle", 2 to "car", 3 to "motorcycle", 5 to "bus", 7 to "truck")
            for (i in 0 until count) { val id = classes[0][i].toInt(); val score = scores[0][i]; val b = boxes[0][i]; if (allowed.containsKey(id) && score >= scoreThreshold && score.isFinite() && b.all { it.isFinite() } && b[0] <= b[2] && b[1] <= b[3]) detections += mapOf("classId" to id, "score" to score, "box" to listOf(b[0], b[1], b[2], b[3])) }
            return mapOf("detectorSha256" to modelSha256, "thresholdPolicyVersion" to thresholdPolicyVersion, "detections" to detections, "inferenceMs" to ((System.nanoTime() - started) / 1_000_000L))
        } finally { oriented.recycle() }
    }

    private fun preprocess(source: Bitmap): ByteBuffer { val scale=min(320.0/source.width,320.0/source.height); val w=(source.width*scale).toInt().coerceAtLeast(1); val h=(source.height*scale).toInt().coerceAtLeast(1); val resized=Bitmap.createScaledBitmap(source,w,h,true); val canvas=Bitmap.createBitmap(320,320,Bitmap.Config.ARGB_8888); Canvas(canvas).apply { drawColor(Color.BLACK); drawBitmap(resized,((320-w)/2).toFloat(),((320-h)/2).toFloat(),Paint(Paint.FILTER_BITMAP_FLAG)) }; resized.recycle(); val pixels=IntArray(320*320); canvas.getPixels(pixels,0,320,0,0,320,320); val input=ByteBuffer.allocateDirect(320*320*3).order(ByteOrder.nativeOrder()); for (p in pixels) { input.put(((p shr 16) and 255).toByte()); input.put(((p shr 8) and 255).toByte()); input.put((p and 255).toByte()) }; canvas.recycle(); input.rewind(); return input }
    private fun orient(bitmap: Bitmap, file: File): Bitmap { val o=try { ExifInterface(file).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL) } catch (_:Throwable) { ExifInterface.ORIENTATION_NORMAL }; val m=Matrix(); when(o){ExifInterface.ORIENTATION_ROTATE_90->m.postRotate(90f);ExifInterface.ORIENTATION_ROTATE_180->m.postRotate(180f);ExifInterface.ORIENTATION_ROTATE_270->m.postRotate(270f);else->return bitmap}; return Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,m,true) }
    private fun sha256(bytes: ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){ "%02x".format(it) }
    override fun close(){ executor.shutdown(); synchronized(this){interpreter?.close();interpreter=null} }
    companion object { const val modelAsset="models/iris_v0_efficientdet_lite0.tflite"; const val modelSha256="2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b"; const val scoreThreshold=0.30f; const val thresholdPolicyVersion="v1-score-threshold-0.30" }
}
