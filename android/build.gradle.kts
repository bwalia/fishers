plugins {
    alias(libs.plugins.android.application) apply false
    // No `kotlin.android`: AGP 9 brings Kotlin support with it and refuses the
    // separate plugin. Compose and serialization are still their own.
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
