plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.iris.incidentreconstruction"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.iris.incidentreconstruction"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

val verifyIrisGeneratedPluginRegistration by tasks.registering {
    group = "verification"
    description = "Verifies that Flutter generated the Android sqflite registration."

    doLast {
        val pluginMetadata = rootProject.file("../.flutter-plugins-dependencies")
        val generatedRegistrant =
            file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")

        check(pluginMetadata.isFile) {
            "Flutter plugin metadata is missing. Run flutter pub get before building."
        }
        val metadata = pluginMetadata.readText()
        val requiredPlugins =
            listOf("camera_android_camerax", "image_picker_android", "path_provider_android", "sqflite_android")
        requiredPlugins.forEach { plugin ->
            check(Regex(""""name"\s*:\s*"$plugin"""").containsMatchIn(metadata)) {
                "Flutter plugin metadata omits $plugin. Run flutter clean and flutter pub get."
            }
        }
        check(generatedRegistrant.isFile) {
            "Flutter's GeneratedPluginRegistrant.java is missing."
        }
        check(
            generatedRegistrant
                .readText()
                .contains("new com.tekartik.sqflite.SqflitePlugin()"),
        ) {
            "GeneratedPluginRegistrant does not register SqflitePlugin."
        }
        check(
            generatedRegistrant
                .readText()
                .contains("new io.flutter.plugins.camerax.CameraAndroidCameraxPlugin()"),
        ) {
            "GeneratedPluginRegistrant does not register CameraAndroidCameraxPlugin."
        }
        check(
            generatedRegistrant
                .readText()
                .contains("new io.flutter.plugins.imagepicker.ImagePickerPlugin()"),
        ) {
            "GeneratedPluginRegistrant does not register ImagePickerPlugin."
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(verifyIrisGeneratedPluginRegistration)
}
