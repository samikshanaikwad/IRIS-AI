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

    // Ignored, local-only MobileSAM qualification exports. This source set is
    // debug-only; release APKs never include the experimental model artifacts.
    sourceSets.getByName("debug").assets.srcDir(
        rootProject.file("../../.local-tools/segmentation-qualification/export"),
    )

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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.30.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    // Official OpenCV Android AAR from Maven Central; infrastructure only.
    implementation("org.opencv:opencv:4.10.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.2.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
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
    dependsOn(verifyIrisDetectorModel)
    dependsOn(verifyIrisDepthModel)
}

val verifyIrisDepthModel by tasks.registering {
    group = "verification"
    description = "Verifies the qualified ORT depth model asset hash."
    doLast {
        val asset = file("src/main/assets/models/iris_v0_depth_vits_518.ort")
        check(asset.isFile) { "Required V0 depth asset is missing." }
        val digest = MessageDigest.getInstance("SHA-256").digest(asset.readBytes())
            .joinToString("") { "%02x".format(it) }
        check(digest == "f983ac210c302d37e0c07b075575426a4694a2b6eed6414fe66339bcb75a6830") {
            "V0 depth asset hash mismatch."
        }
    }
}

val verifyIrisDetectorModel by tasks.registering {
    group = "verification"
    doLast {
        val asset = file("src/main/assets/models/iris_v0_efficientdet_lite0.tflite")
        check(asset.isFile) { "Required V0 detector asset is missing." }
        val digest = MessageDigest.getInstance("SHA-256").digest(asset.readBytes()).joinToString("") { "%02x".format(it) }
        check(digest == "2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b") { "V0 detector asset hash mismatch." }
    }
}
