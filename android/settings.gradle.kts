// The Kotlin + Compose app. Replaces `flutter/`, which reached a foundation and
// a first vertical slice before we changed course: Flutter's case is one
// codebase for both phones, and iOS is already 26k lines of native SwiftUI, so
// here it was paying a runtime and a toolchain for a single platform.
//
// `flutter/PARITY.md` survives the change and is still the map — it inventories
// every iOS screen, store, model and endpoint against where its Android
// counterpart goes. `ios/Fishers/` remains the specification.

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Fishers"
include(":app")
