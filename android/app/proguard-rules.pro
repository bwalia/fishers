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
