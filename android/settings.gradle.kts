pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// Patch for ffmpeg_kit_flutter_min_gpl to add namespace
gradle.beforeSettings {
    val userHome = System.getProperty("user.home")
    val ffmpegPath = "$userHome/.pub-cache/hosted/pub.dev/ffmpeg_kit_flutter_min_gpl-5.1.0/android/build.gradle"
    val ffmpegFile = File(ffmpegPath)
    if (ffmpegFile.exists()) {
        val content = ffmpegFile.readText()
        if (!content.contains("namespace")) {
            val newContent = content.replace(
                "android {",
                "android {\n    namespace \"com.arthenica.ffmpegkit.flutter.min_gpl\""
            )
            ffmpegFile.writeText(newContent)
            println("✅ Namespace added to ffmpeg_kit_flutter_min_gpl")
        } else {
            println("ℹ️ Namespace already exists in ffmpeg_kit_flutter_min_gpl")
        }
    } else {
        println("⚠️ ffmpeg_kit_flutter_min_gpl build.gradle not found at $ffmpegPath")
    }
}