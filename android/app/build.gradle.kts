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

// Ezy release signing — android/key_ezy.properties (gitignored) holds ONLY
// storeFile + keyAlias. The password is read from the EZY_KEY_PASSWORD
// environment variable at build time, so it is never stored in the project.
val ezyKeystoreProperties = Properties()
val ezyKeystorePropertiesFile = rootProject.file("key_ezy.properties")
if (ezyKeystorePropertiesFile.exists()) {
    ezyKeystorePropertiesFile.inputStream().use { ezyKeystoreProperties.load(it) }
}
val ezyKeyPassword: String? = System.getenv("EZY_KEY_PASSWORD")

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
        // Ezy release key = the native Ezy keystore (SHA-1 DF:BE:EC:9D…), so the
        // Flutter Ezy app can update the live native Ezy app. Path + alias come
        // from android/key_ezy.properties; the password ONLY from the
        // EZY_KEY_PASSWORD environment variable (never saved in the project).
        create("ezyRelease") {
            keyAlias = ezyKeystoreProperties["keyAlias"] as String?
            keyPassword = ezyKeyPassword
            storeFile = (ezyKeystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = ezyKeyPassword
        }
    }

        buildTypes {
        release {
            // Release is ALWAYS signed with the real production key — no silent debug
            // fallback. The key is chosen per flavor (see productFlavors below:
            // magik → "release", ezy → "ezyRelease"). If a key is missing, the
            // release build fails loud (see the task-graph guard after the
            // android { } block). Debug/profile keep the debug key.

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
            // Same package id as the native Android app (magikdigi build.gradle, flavor "cloud").
            applicationId = "com.itp.ezycabledigi.androidapp"
            resValue("string", "app_name", "Ezy Cable Digi")
            // Release only: debug/profile build types keep their own debug key.
            signingConfig = signingConfigs.getByName("ezyRelease")
        }

        create("magik") {
            dimension = "default"
            // Same package id as the native Android app (magikdigi build.gradle, flavor "kccl").
            applicationId = "itp.com.magikdigi"
            resValue("string", "app_name", "Magik Digi")
            // Same MagikDigi key as before (android/key.properties).
            signingConfig = signingConfigs.getByName("release")
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
    // Ezy release also needs the Ezy key file + its password in the environment.
    val buildingEzyRelease = allTasks.any { it.name.contains("EzyRelease") }
    if (buildingEzyRelease && !ezyKeystorePropertiesFile.exists()) {
        throw GradleException(
            "Ezy release build requires android/key_ezy.properties " +
            "(storeFile + keyAlias of the native Ezy keystore)."
        )
    }
    if (buildingEzyRelease && ezyKeyPassword.isNullOrEmpty()) {
        throw GradleException(
            "Ezy release build requires the EZY_KEY_PASSWORD environment variable " +
            "(the native Ezy keystore password). Set it in this terminal, then build again."
        )
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
