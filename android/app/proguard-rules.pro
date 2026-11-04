# kotlinx.serialization keeps its generated serializers by annotation; R8 needs
# telling, or a release build decodes every API response into nothing.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.fishers.app.** {
    *** Companion;
}
-keepclasseswithmembers class com.fishers.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Tink, which androidx.security-crypto brings in for the encrypted token store,
# is annotated with ErrorProne's annotations. Those are compile-time only and
# genuinely absent at runtime, so R8 is right that they are missing and wrong
# that it matters. Without this the first release build anybody ever ran failed
# on it — debug builds do not minify, so nothing had exercised R8 before.
-dontwarn com.google.errorprone.annotations.**

# JNA, and the uniffi bindings that ride on it. The cricket engine is Rust
# reached through `uniffi.fishers_ffi`, which uses JNA — and JNA finds fields
# like `Pointer.peer` by name from its own native side. R8 renames them, so a
# release build loads the library and then cannot talk to it:
#
#   This match's book would not replay:
#   Can't obtain peer field ID for class com.sun.jna.Pointer
#
# Debug builds do not minify, which is why scoring worked everywhere except
# the only build that ships.
-keep class com.sun.jna.** { *; }
-keep interface com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
-keep class uniffi.fishers_ffi.** { *; }
-dontwarn java.awt.**
