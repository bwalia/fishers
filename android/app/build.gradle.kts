plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.fishers.app"
    compileSdk = 36

    defaultConfig {
        // The same id the Flutter build used: one product, one Play listing.
        // This app replaces that one rather than sitting beside it.
        applicationId = "com.fishers.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // The engine is built for these three, and JNA would otherwise bring a
        // dispatcher for mips and mips64 as well — architectures Android
        // dropped long ago.
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }

        // What Info.plist is on iOS: the server baked in at build time, which
        // the settings panel and the process environment can still override.
        // Empty by default so a developer build falls through to the emulator
        // loopback rather than to production.
        buildConfigField(
            "String",
            "FISHERS_API_URL",
            "\"${project.findProperty("fishers.apiUrl") ?: ""}\"",
        )
    }

    buildTypes {
        debug {
            // An emulator's own 127.0.0.1 is the emulator, so the address that
            // reaches scripts/start.sh on the developer's Mac is 10.0.2.2.
            // Same fallback the Flutter and iOS builds use.
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Falls back to the debug key so `assembleRelease` works on a
            // machine with no keystore; the store upload lives in its own
            // workflow, which always writes one first.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    testOptions {
        unitTests.all {
            // The JVM tests call the real engine through the real bindings, so
            // JNA has to find the host build of it. This is what makes those
            // tests worth having: they exercise Rust, not a stand-in.
            it.systemProperty(
                "jna.library.path",
                rootProject.file("../backend/target/debug").absolutePath,
            )
            it.dependsOn("cargoBuildHost")
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.navigation.compose)
    debugImplementation(libs.androidx.compose.ui.tooling)

    // The generated engine bindings call through JNA.
    implementation(variantOf(libs.jna) { artifactType("aar") })

    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.retrofit)
    implementation(libs.retrofit.kotlinx.serialization)

    testImplementation(libs.junit)
    // The aar carries Android's native dispatcher and no desktop one, so the
    // JVM tests get the plain jar. Same JNA, different platform stubs.
    testImplementation(libs.jna)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}

// ---------------------------------------------------------------------------
// The cricket engine, built from Rust and bound into Kotlin.
//
// `backend/ffi` is the one implementation of the Laws. This wires it in so
// `./gradlew assembleDebug` produces the .so for each ABI and the Kotlin that
// calls it. Neither is committed: generated code that lives in the repo drifts
// from the source it came from, which is the exact failure this ends.
//
// It needs a Rust toolchain and the NDK. That is not an accident — the engine
// is Rust now, and a build that quietly skipped it would ship an app whose
// scoring rules are missing rather than wrong.
// ---------------------------------------------------------------------------

/** An `Exec` that also declares where it writes, which is what the variant API
 *  needs before it will wire a generated directory into the build. */
abstract class RustExec : Exec() {
    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty
}

val rustRoot = rootProject.file("../backend")
val engineAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

/** Where cargo is, whether or not Gradle inherited a login shell's PATH. */
fun cargoBin(name: String): String = listOf(
    File(System.getProperty("user.home"), ".cargo/bin/$name"),
    File("/opt/homebrew/bin/$name"),
    File("/usr/local/bin/$name"),
).firstOrNull { it.canExecute() }?.absolutePath ?: name

/** The NDK, from the environment or the newest one the SDK has installed. */
fun ndkHome(): String? {
    System.getenv("ANDROID_NDK_HOME")?.takeIf { File(it).isDirectory }?.let { return it }
    val sdk = System.getenv("ANDROID_HOME")
        ?: System.getenv("ANDROID_SDK_ROOT")
        ?: File(System.getProperty("user.home"), "Library/Android/sdk")
            .takeIf { it.isDirectory }?.absolutePath
        ?: return null
    return File(sdk, "ndk").listFiles()?.filter { it.isDirectory }
        ?.maxByOrNull { it.name }?.absolutePath
}

/** The host build the binding generator reads. */
val cargoBuildHost by tasks.registering(Exec::class) {
    group = "rust"
    description = "Build the engine for this machine, for the generator to read"
    workingDir = rustRoot
    commandLine(cargoBin("cargo"), "build", "-q", "-p", "fishers-ffi")
    inputs.dir(File(rustRoot, "ffi/src"))
    inputs.dir(File(rustRoot, "domain/src"))
    outputs.file(File(rustRoot, "target/debug/libfishers_ffi.dylib"))
}

val cargoBuildEngine by tasks.registering(RustExec::class) {
    group = "rust"
    description = "Cross-compile the cricket engine for every Android ABI"
    workingDir = rustRoot
    outputDir.set(layout.buildDirectory.dir("rustJniLibs"))
    doFirst {
        val ndk = ndkHome() ?: throw GradleException(
            "No Android NDK found. Set ANDROID_NDK_HOME or install one through the " +
                "SDK Manager — the cricket engine is Rust and has to be cross-compiled."
        )
        environment("ANDROID_NDK_HOME", ndk)
        outputDir.get().asFile.mkdirs()
    }
    // `cargo ndk`, not `cargo-ndk`: it is a cargo subcommand and refuses to run
    // when it is called directly — "This binary may only be called via cargo ndk".
    executable = cargoBin("cargo")
    argumentProviders.add {
        buildList {
            add("ndk")
            engineAbis.forEach { add("-t"); add(it) }
            add("-o"); add(outputDir.get().asFile.absolutePath)
            add("build"); add("--profile"); add("mobile"); add("-p"); add("fishers-ffi")
        }
    }
    inputs.dir(File(rustRoot, "ffi/src"))
    inputs.dir(File(rustRoot, "domain/src"))
}

val generateEngineBindings by tasks.registering(RustExec::class) {
    group = "rust"
    description = "Generate the Kotlin that calls the engine"
    dependsOn(cargoBuildHost)
    workingDir = rustRoot
    outputDir.set(layout.buildDirectory.dir("generatedUniffi"))
    doFirst { outputDir.get().asFile.mkdirs() }
    executable = cargoBin("cargo")
    // Read from the host build, not the .so: reading an Android object on a Mac
    // produces nothing and says nothing about why. The metadata is identical,
    // because it comes from the same source.
    argumentProviders.add {
        listOf(
            "run", "-q", "-p", "fishers-ffi", "--bin", "uniffi-bindgen", "--",
            "generate",
            "--library", File(rustRoot, "target/debug/libfishers_ffi.dylib").absolutePath,
            "--language", "kotlin",
            "--out-dir", outputDir.get().asFile.absolutePath,
        )
    }
    inputs.dir(File(rustRoot, "ffi/src"))
}

androidComponents.onVariants { variant ->
    variant.sources.kotlin?.addGeneratedSourceDirectory(generateEngineBindings) { it.outputDir }
    variant.sources.jniLibs?.addGeneratedSourceDirectory(cargoBuildEngine) { it.outputDir }
}
