@file:Suppress("DEPRECATION_ERROR", "DEPRECATION")
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.mtc.mtcsync"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.mtc.mtcsync"
        minSdk = flutter.minSdkVersion    // 
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Force newer versions of libraries that use deprecated edge-to-edge APIs
    // (setStatusBarColor, setNavigationBarColor, setNavigationBarDividerColor)
    implementation("com.google.android.material:material:1.13.0")
    implementation("androidx.work:work-runtime:2.10.0")
    implementation("androidx.activity:activity:1.10.0")
    // Force core 1.16+ for SHORT_EDGES → ALWAYS cutout mode fix on API 35
    implementation("androidx.core:core-ktx:1.16.0")

    // Force androidx.datastore 1.1.3+ for 16KB page alignment support in libdatastore_shared_counter.so
    implementation("androidx.datastore:datastore-preferences:1.1.3")
    implementation("androidx.datastore:datastore-core:1.1.3")
    
    // Firebase Crashlytics
    implementation("com.google.firebase:firebase-crashlytics-ktx:18.6.0")
    implementation("com.google.firebase:firebase-analytics-ktx:21.5.0")
}

configurations.all {
    resolutionStrategy {
        force("com.google.android.material:material:1.13.0")
        force("androidx.work:work-runtime:2.10.0")
        force("androidx.activity:activity:1.10.0")
        force("androidx.core:core:1.16.0")
        force("androidx.core:core-ktx:1.16.0")
        force("androidx.datastore:datastore-preferences:1.1.3")
        force("androidx.datastore:datastore-preferences-core:1.1.3")
        force("androidx.datastore:datastore-core:1.1.3")
        force("androidx.datastore:datastore:1.1.3")
    }
}
