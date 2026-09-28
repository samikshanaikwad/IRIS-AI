import java.security.MessageDigest

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

    aaptOptions {
        noCompress += "tflite"
    }
}

dependencies {
    implementation("org.tensorflow:tensorflow-lite:2.16.1")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
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

val verifyIrisClassifierModel by tasks.registering {
    group = "verification"
    description = "Verifies bundled V0 classifier assets match the governed hash."

    doLast {
        val expected = "e98d17518b0296a484a0a94c21359a6703b11b56e5db53a1cc659b8b3a440c96"
        val assets = listOf(
            rootProject.file("../assets/models/iris_v0_experimental_mobilenet_v3_small.tflite"),
            file("src/main/assets/models/iris_v0_experimental_mobilenet_v3_small.tflite"),
        )
        assets.forEach { asset ->
            check(asset.isFile) { "Required V0 classifier asset is missing: ${asset.path}" }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(asset.readBytes())
                .joinToString("") { "%02x".format(it) }
            check(digest == expected) { "V0 classifier asset hash mismatch: ${asset.path}" }
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(verifyIrisGeneratedPluginRegistration)
    dependsOn(verifyIrisClassifierModel)
}
