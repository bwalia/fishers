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
