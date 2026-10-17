package com.iris.incidentreconstruction

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Creates bounded, visible-only relative meshes from current persisted source
 * pixels, MobileSAM masks and Depth Anything output.  It does not load a model,
 * infer unseen shape, create a world transform, or emit metric coordinates.
 * Dart verifies provenance and owns durable storage; this class writes only
 * temporary app-cache artifacts.
 */
class IrisPartialSurfaceRuntime(private val context: Context) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            result.error("unavailable", "Partial surface generation is disabled in this build.", null)
            return true
        }
        if (call.method != "generate") return false
        val sourcePath = call.argument<String>("sourceAbsolutePath")
        val depthPath = call.argument<String>("depthAbsolutePath")
        val outputId = call.argument<String>("outputId")
        val contract = call.argument<String>("coordinateContractVersion")
        val masks = call.argument<List<Map<String, Any>>>("masks")
        val dimensions = IntArray(6) { index ->
            call.argument<Number>(when (index) {
                0 -> "orientedWidth"; 1 -> "orientedHeight"; 2 -> "depthWidth";
                3 -> "depthHeight"; 4 -> "depthResizedWidth"; 5 -> "depthResizedHeight";
                else -> error("Unexpected dimension index")
            })?.toInt() ?: -1
        }
        val depthOffsetX = call.argument<Number>("depthOffsetX")?.toInt() ?: -1
        val depthOffsetY = call.argument<Number>("depthOffsetY")?.toInt() ?: -1
        if (sourcePath.isNullOrBlank() || depthPath.isNullOrBlank() || outputId == null ||
            !safeId.matches(outputId) || contract != IrisImageCoordinateContract.VERSION ||
            masks.isNullOrEmpty() || masks.size > maxMasks || dimensions.any { it <= 0 } ||
            depthOffsetX < 0 || depthOffsetY < 0 || dimensions[4] + depthOffsetX > dimensions[2] ||
            depthOffsetY + dimensions[5] > dimensions[3]) {
            result.error("invalid_request", "Current evidence, mask, depth and coordinate metadata are required.", null)
            return true
        }
        executor.execute {
            try {
                val output = generate(
                    sourcePath = sourcePath,
                    depthPath = depthPath,
                    outputId = outputId,
                    orientedWidth = dimensions[0], orientedHeight = dimensions[1],
                    depthWidth = dimensions[2], depthHeight = dimensions[3],
                    resizedWidth = dimensions[4], resizedHeight = dimensions[5],
                    offsetX = depthOffsetX, offsetY = depthOffsetY,
                    rawMasks = masks,
                )
                Handler(Looper.getMainLooper()).post { result.success(output) }
            } catch (_: OutOfMemoryError) {
                Handler(Looper.getMainLooper()).post {
                    result.error("insufficient_memory", "Partial surface generation ran out of memory; no artifact was saved.", null)
                }
            } catch (_: Throwable) {
                Handler(Looper.getMainLooper()).post {
                    result.error("surface_failed", "No valid visible surface could be generated from current evidence.", null)
                }
            }
        }
        return true
    }

    private fun generate(
        sourcePath: String,
        depthPath: String,
        outputId: String,
        orientedWidth: Int,
        orientedHeight: Int,
        depthWidth: Int,
        depthHeight: Int,
        resizedWidth: Int,
        resizedHeight: Int,
        offsetX: Int,
        offsetY: Int,
        rawMasks: List<Map<String, Any>>,
    ): Map<String, Any> {
        val source = privateFile(sourcePath)
        val depth = privateFile(depthPath)
        val decoded = BitmapFactory.decodeFile(source.absolutePath) ?: error("Evidence image decode failed")
        val orientedImage = IrisImageCoordinateContract.orient(decoded, source)
        val image = orientedImage.bitmap
        if (image !== decoded) decoded.recycle()
        require(image.width == orientedWidth && image.height == orientedHeight)
        val values = readDepth(depth, depthWidth, depthHeight)
        val finite = values.filter { it.isFinite() }
        require(finite.size == values.size)
        val minimum = finite.minOrNull() ?: error("Depth is empty")
        val maximum = finite.maxOrNull() ?: error("Depth is empty")
        require(maximum > minimum)
        val baselinePss = currentPssKb()
        val peakPss = AtomicInteger(baselinePss)
        val sampling = AtomicBoolean(true)
        val sampler = Thread {
            while (sampling.get()) {
                peakPss.updateAndGet { old -> max(old, currentPssKb()) }
                try { Thread.sleep(12) } catch (_: InterruptedException) { break }
            }
        }.apply { name = "iris-partial-surface-memory-sampler"; isDaemon = true; start() }
        val started = SystemClock.elapsedRealtimeNanos()
        try {
            val results = ArrayList<Map<String, Any>>()
            var remainingTriangles = maxTotalTriangles
            for (raw in rawMasks) {
                val maskId = raw["maskId"] as? String ?: error("Mask ID missing")
                val detectionIndex = (raw["detectionIndex"] as? Number)?.toInt() ?: error("Detection missing")
                val classId = (raw["classId"] as? Number)?.toInt() ?: error("Class missing")
                val className = raw["className"] as? String ?: error("Class name missing")
                val maskPath = raw["maskAbsolutePath"] as? String ?: error("Mask path missing")
                require(eligibleClasses[classId] == className && detectionIndex >= 0 && safeId.matches(maskId))
                val maskFile = privateFile(maskPath)
                val mask = BitmapFactory.decodeFile(maskFile.absolutePath) ?: error("Mask decode failed")
                try {
                    require(mask.width == orientedWidth && mask.height == orientedHeight)
                    val built = buildSurface(
                        image = image,
                        mask = mask,
                        depths = values,
                        minDepth = minimum,
                        maxDepth = maximum,
                        depthWidth = depthWidth,
                        depthHeight = depthHeight,
                        resizedWidth = resizedWidth,
                        resizedHeight = resizedHeight,
                        offsetX = offsetX,
                        offsetY = offsetY,
                        triangleBudget = min(maxTriangles, remainingTriangles),
                    )
                    if (built.triangles.isEmpty() || built.vertices.size < 3) {
                        results += mapOf(
                            "status" to "INSUFFICIENT_VALID_SURFACE",
                            "maskId" to maskId,
                        )
                        continue
                    }
                    remainingTriangles -= built.triangles.size
                    val destination = File(surfaceDirectory(), "$outputId-$detectionIndex.ips")
                    writeMeshAtomic(destination, built)
                    results += mapOf(
                        "status" to "SURFACE_READY",
                        "maskId" to maskId,
                        "detectionIndex" to detectionIndex,
                        "meshPath" to destination.absolutePath,
                        "meshSha256" to sha256(destination),
                        "vertexCount" to built.vertices.size,
                        "triangleCount" to built.triangles.size,
                    )
                } finally {
                    mask.recycle()
                }
            }
            peakPss.updateAndGet { old -> max(old, currentPssKb()) }
            val totalMs = elapsedMs(started)
            Log.d(
                diagnosticsTag,
                "stage=completed surfaces=${results.count { it["status"] == "SURFACE_READY" }} " +
                    "totalMs=$totalMs baselinePssKb=$baselinePss sampledPeakPssKb=${peakPss.get()}",
            )
            return mapOf(
                "status" to "PARTIAL_SURFACES_GENERATED_ON_DEVICE",
                "processingVersion" to processingVersion,
                "coordinateContractVersion" to IrisImageCoordinateContract.VERSION,
                "surfaceResults" to results,
                "totalMs" to totalMs,
                "baselinePssKb" to baselinePss,
                "sampledPeakPssKb" to peakPss.get(),
            )
        } finally {
            sampling.set(false)
            sampler.interrupt()
            if (Thread.currentThread() != sampler) sampler.join(100)
            image.recycle()
        }
    }

    private fun buildSurface(
        image: Bitmap,
        mask: Bitmap,
        depths: FloatArray,
        minDepth: Float,
        maxDepth: Float,
        depthWidth: Int,
        depthHeight: Int,
        resizedWidth: Int,
        resizedHeight: Int,
        offsetX: Int,
        offsetY: Int,
        triangleBudget: Int,
    ): Surface {
        // Bound mesh density before allocating.  The step derives from the
        // actual valid depth content, not a vehicle size assumption.
        val step = max(4, ceil(sqrt(resizedWidth.toDouble() * resizedHeight / maxVertices.toDouble())).toInt())
        val xs = (offsetX until offsetX + resizedWidth step step).toList()
        val ys = (offsetY until offsetY + resizedHeight step step).toList()
        val vertices = ArrayList<Vertex>(min(maxVertices, xs.size * ys.size))
        val grid = Array(ys.size) { IntArray(xs.size) { -1 } }
        for ((gy, cy) in ys.withIndex()) for ((gx, cx) in xs.withIndex()) {
            val u = ((cx - offsetX + .5) / resizedWidth).coerceIn(0.0, 1.0)
            val v = ((cy - offsetY + .5) / resizedHeight).coerceIn(0.0, 1.0)
            val px = min(image.width - 1, max(0, (u * image.width).toInt()))
            val py = min(image.height - 1, max(0, (v * image.height).toInt()))
            if (!foreground(mask, px, py)) continue
            val raw = depths[cy * depthWidth + cx]
            val nearer = ((raw - minDepth) / (maxDepth - minDepth)).coerceIn(.02f, 1f)
            val z = 1f / nearer
            val color = image.getPixel(px, py) or 0xff000000.toInt()
            grid[gy][gx] = vertices.size
            vertices += Vertex(
                x = ((u - .5) * z).toFloat(),
                y = ((v - .5) * z).toFloat(),
                z = z,
                u = u.toFloat(),
                v = v.toFloat(),
                argb = color,
                rawDepth = raw,
                px = px,
                py = py,
            )
        }
        if (triangleBudget < 1) return Surface(vertices, emptyList())
        val triangles = ArrayList<Triangle>(triangleBudget)
        for (gy in 0 until ys.size - 1) for (gx in 0 until xs.size - 1) {
            if (triangles.size >= triangleBudget) break
            val a = grid[gy][gx]; val b = grid[gy][gx + 1]
            val c = grid[gy + 1][gx]; val d = grid[gy + 1][gx + 1]
            addTriangleIfVisible(triangles, vertices, mask, a, b, d, triangleBudget)
            if (triangles.size < triangleBudget) addTriangleIfVisible(triangles, vertices, mask, a, d, c, triangleBudget)
        }
        return Surface(vertices, triangles)
    }

    private fun addTriangleIfVisible(
        triangles: MutableList<Triangle>, vertices: List<Vertex>, mask: Bitmap,
        a: Int, b: Int, c: Int, triangleBudget: Int,
    ) {
        if (a < 0 || b < 0 || c < 0 || triangles.size >= triangleBudget) return
        val va = vertices[a]; val vb = vertices[b]; val vc = vertices[c]
        val average = (abs(va.rawDepth) + abs(vb.rawDepth) + abs(vc.rawDepth)) / 3f
        val delta = max(va.rawDepth, max(vb.rawDepth, vc.rawDepth)) - min(va.rawDepth, min(vb.rawDepth, vc.rawDepth))
        // Relative-depth discontinuity guard: this is an image-local seam test,
        // not a claim about real depth or vehicle dimensions.
        if (delta > max(.03f, average * .18f)) return
        val edge = arrayOf(
            Pair((va.px + vb.px) / 2, (va.py + vb.py) / 2),
            Pair((vb.px + vc.px) / 2, (vb.py + vc.py) / 2),
            Pair((vc.px + va.px) / 2, (vc.py + va.py) / 2),
            Pair((va.px + vb.px + vc.px) / 3, (va.py + vb.py + vc.py) / 3),
        )
        if (edge.any { (x, y) -> !foreground(mask, x, y) }) return
        triangles += Triangle(a, b, c)
    }

    private fun foreground(mask: Bitmap, x: Int, y: Int): Boolean {
        if (x !in 0 until mask.width || y !in 0 until mask.height) return false
        val colour = mask.getPixel(x, y)
        return ((colour ushr 16) and 255) > 0 || ((colour ushr 8) and 255) > 0 || (colour and 255) > 0
    }

    private fun readDepth(file: File, width: Int, height: Int): FloatArray {
        val bytes = file.readBytes()
        require(bytes.size == width * height * 4)
        return FloatArray(width * height) { index ->
            ByteBuffer.wrap(bytes, index * 4, 4).order(ByteOrder.LITTLE_ENDIAN).float
        }
    }

    private fun writeMeshAtomic(destination: File, surface: Surface) {
        val buffer = ByteBuffer.allocate(headerBytes + surface.vertices.size * vertexBytes + surface.triangles.size * triangleBytes)
            .order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(meshMagic); buffer.putInt(meshVersion)
        buffer.putInt(surface.vertices.size); buffer.putInt(surface.triangles.size)
        for (vertex in surface.vertices) {
            buffer.putFloat(vertex.x); buffer.putFloat(vertex.y); buffer.putFloat(vertex.z)
            buffer.putFloat(vertex.u); buffer.putFloat(vertex.v); buffer.putInt(vertex.argb)
            buffer.putFloat(0f); buffer.putFloat(0f) // reserved for a future documented artifact version
        }
        for (triangle in surface.triangles) {
            buffer.putInt(triangle.a); buffer.putInt(triangle.b); buffer.putInt(triangle.c)
        }
        writeBytesAtomic(destination, buffer.array())
    }

    private fun privateFile(raw: String): File {
        val file = File(raw).canonicalFile
        val root = File(context.applicationInfo.dataDir).canonicalFile
        require(file.path.startsWith(root.path + File.separator) && file.isFile)
        return file
    }

    private fun surfaceDirectory(): File = File(context.cacheDir, "partial-surface").also {
        check(it.isDirectory || it.mkdirs())
    }

    private fun writeBytesAtomic(destination: File, bytes: ByteArray) {
        val temporary = File(destination.parentFile, destination.name + ".part")
        if (temporary.exists()) check(temporary.delete())
        try {
            FileOutputStream(temporary).use { output -> output.write(bytes); output.fd.sync() }
            if (destination.exists()) check(destination.delete())
            check(temporary.renameTo(destination))
        } finally { if (temporary.exists()) temporary.delete() }
    }

    private fun currentPssKb(): Int = try {
        val info = Debug.MemoryInfo(); Debug.getMemoryInfo(info); info.totalPss
    } catch (_: Throwable) { 0 }
    private fun elapsedMs(start: Long) = (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000.0
    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    override fun close() { executor.shutdown() }

    private data class Vertex(
        val x: Float, val y: Float, val z: Float, val u: Float, val v: Float,
        val argb: Int, val rawDepth: Float, val px: Int, val py: Int,
    )
    private data class Triangle(val a: Int, val b: Int, val c: Int)
    private data class Surface(val vertices: List<Vertex>, val triangles: List<Triangle>)

    private companion object {
        const val diagnosticsTag = "IRISPartialSurface"
        const val processingVersion = "iris-visible-surface-v1"
        const val meshMagic = 0x49505331 // IPS1
        const val meshVersion = 1
        const val headerBytes = 16
        const val vertexBytes = 32
        const val triangleBytes = 12
        const val maxVertices = 4096
        const val maxTriangles = 8192
        // A request may contain several real TASK007 masks. Bound the entire
        // operation as well as each part so one evidence item cannot allocate
        // an unbounded scene mesh.
        const val maxTotalTriangles = 12000
        const val maxMasks = 12
        val safeId = Regex("[A-Za-z0-9][A-Za-z0-9_-]{0,127}")
        val eligibleClasses = mapOf(2 to "car", 3 to "motorcycle")
    }
}
