// Djigarlar — Android ilova moduli sozlamasi.
//
// MUHIM: bu fayl ataylab repozitoriyda saqlanadi. `flutter create` mavjud
// fayllarni qayta yozmaydi (--overwrite bermasa), shuning uchun bu yerdagi
// sozlamalar CI'da ham saqlanib qoladi.
//
// `flutter_local_notifications` plagini "core library desugaring" ni talab
// qiladi — u shu yerda yoqilgan.

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uz.djigarlar.djigarlar"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uchun shart
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "uz.djigarlar.djigarlar"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Hozircha debug kalitlar bilan imzolanadi.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
