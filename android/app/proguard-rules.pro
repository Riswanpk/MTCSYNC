# ==============================================================================
# R8 / ProGuard Configuration for MTCSYNC
# ==============================================================================

# Keep essential annotations and signatures for reflection & serialization
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep Parcelable Creator fields for Android IPC
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Kotlin reflection metadata
-keepclassmembers class kotlin.Metadata { *; }

# ==============================================================================
# Plugin Specific Rules (Reflection & Payload Serialization)
# ==============================================================================

# awesome_notifications & notification payloads (uses Gson reflection)
-dontwarn me.carda.awesome_notifications.**
-keep class me.carda.awesome_notifications.** { *; }
-keep class com.google.gson.** { *; }

# flutter_local_notifications (if present/transitive)
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# permission_handler plugin
-keep class com.baseflow.permissionhandler.** { *; }

# package_info_plus plugin
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# call_log plugin
-keep class sk.fourq.calllog.** { *; }

# Keep Kotlin standard library & Coroutines for JNI interop (Dart JNI looks for kotlin.* classes by name)
-keep class kotlin.** { *; }
-keep interface kotlin.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep interface kotlin.coroutines.** { *; }

# JNI-based plugins (jnigen): Dart looks these Java/Kotlin classes up by name at runtime,
# and these plugins ship no consumer rules, so R8 would rename/strip their methods.
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** {
    *;
}
-keepclassmembers class io.flutter.plugins.sharedpreferences.** {
    *;
}
-keep class io.flutter.plugins.pathprovider.** {
    *;
}
-keepclassmembers class io.flutter.plugins.pathprovider.** {
    *;
}

# Keep App specific classes (Application and Activities)
-keep class com.mtc.mtcsync.** { *; }
