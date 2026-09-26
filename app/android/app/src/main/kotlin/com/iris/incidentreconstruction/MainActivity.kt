package com.iris.incidentreconstruction

import com.tekartik.sqflite.SqflitePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Flutter normally registers sqflite through GeneratedPluginRegistrant.
        // Keep a guarded native registration so a stale/empty generated
        // registrant cannot ship an APK whose SQLite method channel has no
        // Android handler.
        if (!flutterEngine.plugins.has(SqflitePlugin::class.java)) {
            flutterEngine.plugins.add(SqflitePlugin())
        }
    }
}
