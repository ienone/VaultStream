plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.vaultstream.frontend"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vaultstream.frontend"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseKeystore = file("release.jks")
    check(releaseKeystore.isFile) {
        "Android builds require frontend/android/app/release.jks; debug signing is disabled."
    }
    fun signingSecret(name: String): String =
        System.getenv(name)?.takeIf { it.isNotBlank() }
            ?: error("Android signing environment variable $name is required.")

    signingConfigs {
        create("release") {
            storeFile = releaseKeystore
            storePassword = signingSecret("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = signingSecret("ANDROID_KEY_ALIAS")
            keyPassword = signingSecret("ANDROID_KEY_PASSWORD")
        }
    }

    // Debug, profile and release must retain the same install identity.
    buildTypes.configureEach {
        signingConfig = signingConfigs.getByName("release")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
