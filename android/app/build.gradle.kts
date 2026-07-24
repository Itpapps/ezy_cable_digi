import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — loaded from android/key.properties (gitignored, never committed).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.ezy_cable_digi"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
         isCoreLibraryDesugaringEnabled = true   
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.ezy_cable_digi"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

        buildTypes {
        release {
            // Release is ALWAYS signed with the real production key — no silent debug
            // fallback. If the key is missing, the release build fails loud (see the
            // task-graph guard after the android { } block). Debug/profile unaffected.
            signingConfig = signingConfigs.getByName("release")

            // ── R8: shrink + obfuscate the Android (Java/Kotlin) half of the app ──
            // Resource shrinking deliberately left OFF for now (one change at a time).
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    flavorDimensions += "default"

    productFlavors {
        create("ezy") {
            dimension = "default"
            applicationId = "com.ezy.cable.digi"
            resValue("string", "app_name", "Ezy Cable Digi")
        }

        create("magik") {
            dimension = "default"
            applicationId = "com.magik.cable.digi"
            resValue("string", "app_name", "Magik Digi")
        }
    }
}

// Fail LOUD only when a RELEASE build is actually requested and the signing key is
// absent. Task-graph time, so debug/profile builds (and IDE sync) are never affected.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { it.name.contains("Release") }
    if (buildingRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Release build requires android/key.properties (the real signing key). " +
            "Debug and profile builds are unaffected."
        )
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
