# ==============================================================================
# R8 / ProGuard Configuration for MTCSYNC
# ==============================================================================

# Keep essential annotations and signatures for reflection & serialization
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep Parcelable Creator fields for Android IPC
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Javascript interfaces if webviews are used
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Kotlin reflection metadata
-keepclassmembers class kotlin.Metadata { *; }

# ==============================================================================
# Don't Warn Rules for Harmless Library Warnings
# Note: Modern SDKs (Firebase, Play Services, OkHttp, gRPC, Flutter plugins)
# ship their own embedded consumer-rules.pro. We do not use blanket `-keep`
# rules here so R8 can achieve high shrinking, obfuscation, and optimization rates.
# ==============================================================================
-dontwarn io.flutter.embedding.engine.FlutterEngine
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**
-dontwarn com.google.firestore.**
-dontwarn io.grpc.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn me.carda.awesome_notifications.**
-dontwarn com.google.android.play.core.**

# Keep Flutter Engine & Plugins for MethodChannels
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep permission_handler plugin
-keep class com.baseflow.permissionhandler.** { *; }

# Keep package_info_plus plugin
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# Keep awesome_notifications plugin
-keep class me.carda.awesome_notifications.** { *; }

# Keep call_log plugin
-keep class sk.fourq.calllog.** { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }

