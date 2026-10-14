package com.iris.incidentreconstruction

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.exifinterface.media.ExifInterface
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Debug-only, isolated MobileSAM qualification runner. It consumes current
 * TASK007 box prompts supplied by the evidence screen and writes only one
 * visualization overlay into app-private cache. It never saves an analysis,
 * mask, or image into the evidence/database repositories.
 */
class IrisSegmentationQualificationRuntime(private val context: Context) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val environment = OrtEnvironment.getEnvironment()
    private var encoder: OrtSession? = null
    private var decoder: OrtSession? = null

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (!context.applicationInfo.flags.let { it and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0 }) {
            result.error("unavailable", "Qualification is debug-build only.", null)
            return true
        }
        if (call.method == "preparePublicEvaluationImage") {
            preparePublicEvaluationImage(call, result)
            return true
        }
        if (call.method != "runQualification") return false
        val path = call.argument<String>("absolutePath")
        val contract = call.argument<String>("coordinateContractVersion")
        val boxes = call.argument<List<Map<String, Any>>>("boxes")
        val outputId = call.argument<String>("outputId") ?: "private-evidence"
        if (path.isNullOrBlank() || contract != IrisImageCoordinateContract.VERSION || boxes.isNullOrEmpty() || boxes.size > 12) {
            result.error("invalid_request", "Current image coordinates and eligible real detections are required.", null)
            return true
        }
        if (!safeId.matches(outputId)) {
            result.error("invalid_request", "Qualification output ID is invalid.", null)
            return true
        }
        executor.execute {
            try {
                val output = runQualification(File(path), boxes, outputId)
                Handler(Looper.getMainLooper()).post { result.success(output) }
            } catch (_: Throwable) {
                Handler(Looper.getMainLooper()).post {
                    result.error("qualification_unavailable", "On-device segmentation qualification did not produce a mask.", null)
                }
            }
        }
        return true
    }

    private fun preparePublicEvaluationImage(call: MethodCall, result: MethodChannel.Result) {
        val assetName = call.argument<String>("assetName")
        val expectedSha256 = call.argument<String>("sha256")
        if (
            assetName == null ||
            !safeAssetName.matches(assetName) ||
            expectedSha256 == null ||
            !sha256Pattern.matches(expectedSha256)
        ) {
            result.error("invalid_request", "A governed public evaluation asset is required.", null)
            return
        }
        executor.execute {
            try {
                val bytes = context.assets.open(assetName).use { it.readBytes() }
                check(sha256(bytes) == expectedSha256)
                val directory = qualificationDirectory()
                val destination = File(directory, "source-$assetName")
                FileOutputStream(destination).use { output ->
                    output.write(bytes)
                    output.fd.sync()
                }
                Handler(Looper.getMainLooper()).post {
                    result.success(
                        mapOf(
                            "absolutePath" to destination.absolutePath,
                            "sha256" to expectedSha256,
                            "bytes" to bytes.size,
                        ),
                    )
                }
            } catch (_: Throwable) {
                Handler(Looper.getMainLooper()).post {
                    result.error(
                        "evaluation_asset_unavailable",
                        "The governed public evaluation image is unavailable or changed.",
                        null,
                    )
                }
            }
        }
    }

    private fun runQualification(
        file: File,
        rawBoxes: List<Map<String, Any>>,
        outputId: String,
    ): Map<String, Any> {
        val canonical = file.canonicalFile
        val appRoot = File(context.applicationInfo.dataDir).canonicalFile
        check(canonical.path.startsWith(appRoot.path + File.separator))
        check(canonical.isFile)
        val boxes = rawBoxes.map { parseBox(it) }
        val bitmap = BitmapFactory.decodeFile(canonical.path) ?: error("Image decode failed")
        val orientedImage = IrisImageCoordinateContract.orient(bitmap, canonical)
        val oriented = orientedImage.bitmap
        if (oriented !== bitmap) bitmap.recycle()
        val directory = qualificationDirectory()
        val outputFile = File(directory, "$outputId-overlay.png")
        val baselinePss = currentPssKb()
        val peakPss = AtomicInteger(baselinePss)
        val sampling = AtomicBoolean(true)
        val sampler = Thread {
            while (sampling.get()) {
                peakPss.updateAndGet { current -> max(current, currentPssKb()) }
                try { Thread.sleep(12) } catch (_: InterruptedException) { break }
            }
        }.apply { name = "iris-segmentation-memory-sampler"; isDaemon = true; start() }
        val allStarted = SystemClock.elapsedRealtimeNanos()
        try {
            val modelLoadStarted = SystemClock.elapsedRealtimeNanos()
            val (encoderSession, decoderSession) = getSessions()
            val modelLoadMs = elapsedMs(modelLoadStarted)
            val preprocessStart = SystemClock.elapsedRealtimeNanos()
            val prepared = prepareSamInput(oriented)
            val imageTensor = OnnxTensor.createTensor(environment, prepared, longArrayOf(1, 3, 1024, 1024))
            val encodeStarted = SystemClock.elapsedRealtimeNanos()
            val embeddingResult = encoderSession.run(mapOf("normalized_image" to imageTensor))
            val encodeMs = elapsedMs(encodeStarted)
            imageTensor.close()
            val embedding = embeddingResult.get("image_embeddings").orElseThrow() as OnnxTensor
            val preparedMs = nanosToMs(encodeStarted - preprocessStart)
            val overlay = oriented.copy(Bitmap.Config.ARGB_8888, true)
            val canvas = Canvas(overlay)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { alpha = 150 }
            val colors = intArrayOf(0xff00bcd4.toInt(), 0xffffa726.toInt(), 0xffab47bc.toInt(), 0xff66bb6a.toInt())
            val perDetection = ArrayList<Map<String, Any>>()
            var wroteAnyMask = false
            val overlayPixels = IntArray(oriented.width * oriented.height)
            for ((index, box) in boxes.withIndex()) {
                val decoderStarted = SystemClock.elapsedRealtimeNanos()
                val resultForBox = runDecoder(decoderSession, embedding, oriented.width, oriented.height, box)
                val decoderMs = elapsedMs(decoderStarted)
                val maskTensor = resultForBox.get("masks").orElseThrow() as OnnxTensor
                val iouTensor = resultForBox.get("iou_predictions").orElseThrow() as OnnxTensor
                val dims = maskTensor.info.shape
                check(dims.size == 4 && dims[0] == 1L && dims[1] == 1L && dims[2] == oriented.height.toLong() && dims[3] == oriented.width.toLong())
                val maskBuffer = maskTensor.floatBuffer
                val totalPixels = oriented.width * oriented.height
                check(maskBuffer.remaining() >= totalPixels)
                var foreground = 0
                var left = oriented.width
                var top = oriented.height
                var right = -1
                var bottom = -1
                overlayPixels.fill(0)
                val maskPixels = IntArray(oriented.width * oriented.height)
                val maskDigest = MessageDigest.getInstance("SHA-256")
                val color = colors[index % colors.size]
                for (y in 0 until oriented.height) {
                    for (x in 0 until oriented.width) {
                        val isForeground = maskBuffer.get(y * oriented.width + x) > 0f
                        maskDigest.update((if (isForeground) 1 else 0).toByte())
                        if (isForeground) {
                            foreground++
                            left = min(left, x); top = min(top, y); right = max(right, x); bottom = max(bottom, y)
                            overlayPixels[y * oriented.width + x] = color
                            maskPixels[y * oriented.width + x] = 0xffffffff.toInt()
                        } else {
                            maskPixels[y * oriented.width + x] = 0xff000000.toInt()
                        }
                    }
                }
                val maskFile = File(directory, "$outputId-mask-$index.png")
                if (foreground > 0) {
                    val maskBitmap = Bitmap.createBitmap(overlayPixels, oriented.width, oriented.height, Bitmap.Config.ARGB_8888)
                    canvas.drawBitmap(maskBitmap, 0f, 0f, paint)
                    maskBitmap.recycle()
                    val binaryMask = Bitmap.createBitmap(
                        maskPixels,
                        oriented.width,
                        oriented.height,
                        Bitmap.Config.ARGB_8888,
                    )
                    FileOutputStream(maskFile).use { output ->
                        check(binaryMask.compress(Bitmap.CompressFormat.PNG, 100, output))
                        output.fd.sync()
                    }
                    binaryMask.recycle()
                    wroteAnyMask = true
                } else if (maskFile.exists()) {
                    check(maskFile.delete())
                }
                val boxArea = max(1.0, (box.right - box.left) * (box.bottom - box.top))
                val maskBoxIou = if (right >= left && bottom >= top) {
                    val intersection = max(0.0, min((right + 1).toDouble(), box.right) - max(left.toDouble(), box.left)) *
                        max(0.0, min((bottom + 1).toDouble(), box.bottom) - max(top.toDouble(), box.top))
                    val maskBoxArea = (right - left + 1.0) * (bottom - top + 1.0)
                    intersection / (boxArea + maskBoxArea - intersection).coerceAtLeast(1.0)
                } else 0.0
                val iouBuffer = iouTensor.floatBuffer
                val predictedQuality = if (iouBuffer.remaining() > 0) iouBuffer.get(0).toDouble() else 0.0
                perDetection += mapOf(
                    "className" to box.className,
                    "score" to box.score,
                    "status" to if (foreground > 0) "MASK_READY" else "EMPTY_MASK",
                    "decoderMs" to decoderMs,
                    "maskPixels" to foreground,
                    "maskRasterSha256" to maskDigest.digest().toHex(),
                    "maskToBoxAreaRatio" to (foreground / boxArea),
                    "maskBoundingBoxIou" to maskBoxIou,
                    "predictedQuality" to predictedQuality,
                    "maskPath" to if (foreground > 0) maskFile.absolutePath else "",
                    "maskFileSha256" to if (foreground > 0) sha256(maskFile) else "",
                )
                resultForBox.close()
            }
            embeddingResult.close()
            check(wroteAnyMask)
            FileOutputStream(outputFile).use { output ->
                check(overlay.compress(Bitmap.CompressFormat.PNG, 100, output))
                output.fd.sync()
            }
            overlay.recycle()
            val outputHash = sha256(outputFile)
            val pssAtReturn = currentPssKb()
            peakPss.updateAndGet { current -> max(current, pssAtReturn) }
            return mapOf(
                "status" to "MASKS_GENERATED_ON_DEVICE",
                "model" to "MobileSAM ViT-T",
                "modelSourceCommit" to upstreamCommit,
                "encoderSha256" to encoderSha256,
                "decoderSha256" to decoderSha256,
                "coordinateContractVersion" to IrisImageCoordinateContract.VERSION,
                "orientedWidth" to oriented.width,
                "orientedHeight" to oriented.height,
                "modelLoadMs" to modelLoadMs,
                "preprocessMs" to preparedMs,
                "imageEncoderMs" to encodeMs,
                "promptMaskResults" to perDetection,
                "totalMs" to elapsedMs(allStarted),
                "sampledPeakPssKb" to peakPss.get(),
                "baselinePssKb" to baselinePss,
                "peakPssDeltaKb" to max(0, peakPss.get() - baselinePss),
                "overlayPath" to outputFile.absolutePath,
                "overlaySha256" to outputHash,
            )
        } finally {
            sampling.set(false)
            sampler.interrupt()
            if (Thread.currentThread() != sampler) sampler.join(100)
            oriented.recycle()
        }
    }

    private data class PromptBox(val className: String, val score: Double, val left: Double, val top: Double, val right: Double, val bottom: Double)

    private fun parseBox(raw: Map<String, Any>): PromptBox {
        val id = (raw["classId"] as? Number)?.toInt() ?: error("class missing")
        val className = raw["className"] as? String ?: error("class name missing")
        check(eligibleClasses[id] == className)
        val score = (raw["score"] as? Number)?.toDouble() ?: error("score missing")
        val coords = (raw["box"] as? List<*>)?.map { (it as? Number)?.toDouble() ?: error("box coordinate missing") } ?: error("box missing")
        check(score.isFinite() && score in 0.30..1.0 && coords.size == 4 && coords.all(Double::isFinite))
        val (left, top, right, bottom) = coords
        check(left >= 0 && top >= 0 && left < right && top < bottom)
        return PromptBox(className, score, left, top, right, bottom)
    }

    private fun getSessions(): Pair<OrtSession, OrtSession> {
        if (encoder == null) {
            val encoderBytes = context.assets.open("mobilesam_vit_t_encoder.onnx").use { it.readBytes() }
            val decoderBytes = context.assets.open("mobilesam_vit_t_box_decoder.onnx").use { it.readBytes() }
            check(sha256(encoderBytes) == encoderSha256 && sha256(decoderBytes) == decoderSha256)
            val options = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(4)
                setInterOpNumThreads(1)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            }
            try {
                encoder = environment.createSession(encoderBytes, options)
                decoder = environment.createSession(decoderBytes, options)
            } finally { options.close() }
        }
        return Pair(checkNotNull(encoder), checkNotNull(decoder))
    }

    private fun runDecoder(session: OrtSession, embedding: OnnxTensor, width: Int, height: Int, box: PromptBox): OrtSession.Result {
        val scale = 1024.0 / max(width, height)
        val coords = arrayOf(arrayOf(
            floatArrayOf((box.left * scale).toFloat(), (box.top * scale).toFloat()),
            floatArrayOf((box.right * scale).toFloat(), (box.bottom * scale).toFloat()),
        ))
        val labels = arrayOf(floatArrayOf(2f, 3f))
        val pointTensor = OnnxTensor.createTensor(environment, coords)
        val labelTensor = OnnxTensor.createTensor(environment, labels)
        val maskTensor = OnnxTensor.createTensor(environment, Array(1) { Array(1) { Array(256) { FloatArray(256) } } })
        val hasMaskTensor = OnnxTensor.createTensor(environment, floatArrayOf(0f))
        val sizeTensor = OnnxTensor.createTensor(environment, floatArrayOf(height.toFloat(), width.toFloat()))
        try {
            return session.run(mapOf(
                "image_embeddings" to embedding,
                "point_coords" to pointTensor,
                "point_labels" to labelTensor,
                "mask_input" to maskTensor,
                "has_mask_input" to hasMaskTensor,
                "orig_im_size" to sizeTensor,
            ), setOf("masks", "iou_predictions"))
        } finally {
            pointTensor.close(); labelTensor.close(); maskTensor.close(); hasMaskTensor.close(); sizeTensor.close()
        }
    }

    private fun prepareSamInput(image: Bitmap): FloatBuffer {
        val scale = 1024.0 / max(image.width, image.height)
        val width = (image.width * scale).roundToInt().coerceIn(1, 1024)
        val height = (image.height * scale).roundToInt().coerceIn(1, 1024)
        val resized = Bitmap.createScaledBitmap(image, width, height, true)
        val pixels = IntArray(width * height)
        resized.getPixels(pixels, 0, width, 0, 0, width, height)
        if (resized !== image) resized.recycle()
        val output = ByteBuffer.allocateDirect(3 * 1024 * 1024 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        val channelSize = 1024 * 1024
        for (y in 0 until height) for (x in 0 until width) {
            val pixel = pixels[y * width + x]
            val index = y * 1024 + x
            output.put(index, (((pixel shr 16) and 255) - 123.675f) / 58.395f)
            output.put(channelSize + index, (((pixel shr 8) and 255) - 116.28f) / 57.12f)
            output.put(2 * channelSize + index, ((pixel and 255) - 103.53f) / 57.375f)
        }
        pixels.fill(0)
        output.position(0)
        return output
    }

    private fun currentPssKb(): Int = try {
        val info = Debug.MemoryInfo()
        Debug.getMemoryInfo(info)
        info.totalPss
    } catch (_: Throwable) { 0 }

    private fun elapsedMs(start: Long) = nanosToMs(SystemClock.elapsedRealtimeNanos() - start)
    private fun nanosToMs(nanos: Long) = nanos / 1_000_000.0
    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toHex()
    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).toHex()
    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }
    private fun qualificationDirectory(): File =
        File(context.cacheDir, "segmentation-qualification").also {
            check(it.isDirectory || it.mkdirs())
        }

    override fun close() {
        executor.shutdown()
        encoder?.close(); encoder = null
        decoder?.close(); decoder = null
    }

    private companion object {
        const val upstreamCommit = "f706ad9c4eb7f219c00d9050e46328518ffb65d2"
        const val encoderSha256 = "f55b0f6c6949d4737ba06ddf14b99b35ae7c26c782f9865078e34b0a0f45df49"
        const val decoderSha256 = "4a3d6ee977ce5ad077e1ab980db5f1bffb96758c4029a2abccd0d08634a8bf63"
        val eligibleClasses = mapOf(1 to "bicycle", 2 to "car", 3 to "motorcycle", 5 to "bus", 7 to "truck")
        val safeId = Regex("[a-z0-9][a-z0-9_-]{0,63}")
        val safeAssetName = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
        val sha256Pattern = Regex("[0-9a-f]{64}")
    }
}
