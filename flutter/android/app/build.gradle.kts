import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase, when there is a project to talk to.
//
// google-services.json comes from the Firebase console and is gitignored, for
// the same reason key.properties is: it belongs to whoever owns the project,
// not to the repo. The plugin refuses to configure without it — "File
// google-services.json is missing" — which would fail every build on a
// machine that has not got one, including CI's APK job.
//
// So it is applied only when the file is there. Without it the app still
// builds and runs; `Firebase.initializeApp()` finds no default options, and
// PushRegistrar treats that the way the server treats a missing APNs key:
// push is off, the bell still fills up, and only the buzz is missing.
if (rootProject.file("app/google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing, when there is a keystore to sign with.
//
// CI writes android/key.properties and the .jks beside it from secrets; both
// are gitignored and neither exists on a developer's machine. When the file is
// absent the release build falls back to the debug key below, so
// `flutter run --release` keeps working locally — but an unsigned-for-store
// build can never be uploaded by accident, because the upload only happens in
// the release workflow, which always writes this file first.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.fishers.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The same identifier as the iPhone app's bundle id: the two stores are
        // separate namespaces, and sharing it keeps the product one product.
        applicationId = "com.fishers.app"
        // Android 8.0. The brief's floor, and above flutter_secure_storage's.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No keystore here — debug keys, so a local release build runs.
                signingConfigs.getByName("debug")
            }
            // Play wants the mapping file to symbolicate crashes, and the
            // shrinker is what makes it worth having.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
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
