package com.iris.incidentreconstruction

import android.content.pm.ApplicationInfo
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // FlutterActivity normally reaches this registrant through reflection.
        // Invoke the generated app registrant directly so this engine has one
        // explicit, observable, standard registration path.
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        val generatedRegistrantInvoked = true

        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            installPluginRegistrationDiagnostics(
                flutterEngine,
                generatedRegistrantInvoked,
            )
        }
    }

    private fun installPluginRegistrationDiagnostics(
        flutterEngine: FlutterEngine,
        generatedRegistrantInvoked: Boolean,
    ) {
        val sqflitePluginClass = resolveSqflitePluginClass()
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
                    ),
                )
            } else {
                result.notImplemented()
            }
        }
    }

    private fun resolveSqflitePluginClass(): Class<out FlutterPlugin>? =
        try {
            Class.forName(sqflitePluginClassName).asSubclass(FlutterPlugin::class.java)
        } catch (error: ClassNotFoundException) {
            Log.e(diagnosticsTag, "SqflitePlugin class is not packaged.", error)
            null
        }

    private companion object {
        const val diagnosticsTag = "IRISPluginRegistration"
        const val diagnosticsChannel = "com.iris.debug/plugin_registration"
        const val diagnosticsMethod = "getRegistrationState"
        const val sqflitePluginClassName = "com.tekartik.sqflite.SqflitePlugin"
    }
}
