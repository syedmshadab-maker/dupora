plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dupora.dupora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.dupora.dupora"
        // Android 11 (API 30) per project spec: scoped storage + SAF is the
        // baseline this app is designed against, so we don't try to support
        // (and branch behavior for) pre-scoped-storage semantics.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // No production keystore exists in this environment (it must be
            // provided by whoever owns the Play Store listing, not fabricated
            // here). Signed with the debug key so `flutter build apk --release`
            // still produces an installable artifact for local/CI testing; see
            // BUILD.md for wiring a real release-signing config.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
