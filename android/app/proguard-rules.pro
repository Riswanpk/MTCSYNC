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

# Keep App specific classes (Application and Activities)
-keep class com.mtc.mtcsync.** { *; }

# Keep Flutter plugin callback and method channel interfaces
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$RequestPermissionsResultListener { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$ActivityResultListener { *; }

