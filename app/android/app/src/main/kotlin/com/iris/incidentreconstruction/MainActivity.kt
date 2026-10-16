package com.iris.incidentreconstruction

import android.content.pm.ApplicationInfo
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    private var classifierRuntime: IrisClassifierRuntime? = null
    private var objectDetectorRuntime: IrisObjectDetectorRuntime? = null
    private var depthRuntime: IrisDepthRuntime? = null
    private var multiViewRuntime: IrisMultiViewRuntime? = null
    private var locationRuntime: IrisLocationRuntime? = null
    private var segmentationQualificationRuntime: IrisSegmentationQualificationRuntime? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // FlutterActivity normally reaches this registrant through reflection.
        // Invoke the generated app registrant directly so this engine has one
        // explicit, observable, standard registration path.
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        val generatedRegistrantInvoked = true
        val runtime = IrisClassifierRuntime(applicationContext)
        classifierRuntime = runtime
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, classifierChannel)
            .setMethodCallHandler { call, result ->
                if (!runtime.handle(call, result)) result.notImplemented()
            }
        val detector = IrisObjectDetectorRuntime(applicationContext)
        objectDetectorRuntime = detector
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, detectorChannel)
            .setMethodCallHandler { call, result -> if (!detector.handle(call, result)) result.notImplemented() }
        val depth = IrisDepthRuntime(applicationContext)
        depthRuntime = depth
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, depthChannel)
            .setMethodCallHandler { call, result -> if (!depth.handle(call, result)) result.notImplemented() }
        val multiView = IrisMultiViewRuntime()
        multiViewRuntime = multiView
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, multiViewChannel)
            .setMethodCallHandler { call, result -> if (!multiView.handle(call, result)) result.notImplemented() }
        val location = IrisLocationRuntime(this)
        locationRuntime = location
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannel)
            .setMethodCallHandler { call, result -> if (!location.handle(call, result)) result.notImplemented() }

        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            val segmentation = IrisSegmentationQualificationRuntime(applicationContext)
            segmentationQualificationRuntime = segmentation
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                segmentationQualificationChannel,
            ).setMethodCallHandler { call, result ->
                if (!segmentation.handle(call, result)) result.notImplemented()
            }
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                segmentationChannel,
            ).setMethodCallHandler { call, result ->
                if (!segmentation.handleEvidence(call, result)) result.notImplemented()
            }
            installPluginRegistrationDiagnostics(
                flutterEngine,
                generatedRegistrantInvoked,
            )
        }
    }

    override fun onDestroy() {
        classifierRuntime?.close()
        classifierRuntime = null
        objectDetectorRuntime?.close()
        objectDetectorRuntime = null
        depthRuntime?.close()
        depthRuntime = null
        multiViewRuntime = null
        locationRuntime = null
        segmentationQualificationRuntime?.close()
        segmentationQualificationRuntime = null
        super.onDestroy()
    }

    private fun installPluginRegistrationDiagnostics(
        flutterEngine: FlutterEngine,
        generatedRegistrantInvoked: Boolean,
    ) {
        val sqflitePluginClass = resolvePluginClass(sqflitePluginClassName)
        val classAvailable = sqflitePluginClass != null
        val pluginRegistered =
            sqflitePluginClass?.let { pluginClass ->
                flutterEngine.plugins.has(pluginClass)
            } ?: false

        Log.d(
            diagnosticsTag,
            "MainActivity engine: " +
                "generatedRegistrantInvoked=$generatedRegistrantInvoked, " +
                "sqfliteClassAvailable=$classAvailable, " +
                "sqfliteRegistered=$pluginRegistered",
        )

        val pluginStates = pluginClassNames.mapValues { (_, className) ->
            val pluginClass = resolvePluginClass(className)
            mapOf(
                "classAvailable" to (pluginClass != null),
                "registered" to
                    (pluginClass?.let { flutterEngine.plugins.has(it) } ?: false),
            )
        }
        Log.d(diagnosticsTag, "MainActivity engine plugin states: $pluginStates")

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            diagnosticsChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == diagnosticsMethod) {
                result.success(
                    mapOf(
                        "activity" to MainActivity::class.java.name,
                        "generatedRegistrantInvoked" to generatedRegistrantInvoked,
                        "sqfliteClassAvailable" to classAvailable,
                        "sqfliteRegistered" to pluginRegistered,
                        "plugins" to pluginStates,
                    ),
                )
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            environmentDiagnosticsChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == environmentDiagnosticsMethod) {
                // Count-only development diagnostics. Flutter controls the
                // message and deliberately omits coordinates and payloads.
                val message = call.argument<String>("message")
                if (message != null && message.length <= 1000) {
                    Log.d(environmentDiagnosticsTag, message)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun resolvePluginClass(className: String): Class<out FlutterPlugin>? =
        try {
            Class.forName(className).asSubclass(FlutterPlugin::class.java)
        } catch (error: ClassNotFoundException) {
            Log.e(diagnosticsTag, "Flutter plugin class is not packaged: $className", error)
            null
        }

    private companion object {
        const val diagnosticsTag = "IRISPluginRegistration"
        const val diagnosticsChannel = "com.iris.debug/plugin_registration"
        const val diagnosticsMethod = "getRegistrationState"
        const val environmentDiagnosticsTag = "IRISEnvironment"
        const val environmentDiagnosticsChannel = "com.iris.debug/environment"
        const val environmentDiagnosticsMethod = "logCounts"
        const val classifierChannel = "com.iris.classifier/v1"
        const val detectorChannel = "com.iris.detector/v1"
        const val depthChannel = "com.iris.depth/v1"
        const val multiViewChannel = "com.iris.multiview/v1"
        const val locationChannel = "com.iris.location/v1"
        const val segmentationQualificationChannel = "com.iris.debug/segmentation-qualification"
        const val segmentationChannel = "com.iris.segmentation/v1"
        internal val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        const val sqflitePluginClassName = "com.tekartik.sqflite.SqflitePlugin"
        val pluginClassNames = mapOf(
            "camera" to "io.flutter.plugins.camerax.CameraAndroidCameraxPlugin",
            "image_picker" to "io.flutter.plugins.imagepicker.ImagePickerPlugin",
            "sqflite" to sqflitePluginClassName,
            "jni" to "com.github.dart_lang.jni.JniPlugin",
            "jni_flutter" to "com.github.dart_lang.jni_flutter.JniFlutterPlugin",
        )
    }
}
