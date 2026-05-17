import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.glaze.flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("ci") {
            val ks = System.getenv("KEYSTORE_BASE64")
            if (ks != null) {
                val ksFile = rootProject.file("debug-key.keystore")
                if (!ksFile.exists()) {
                    ksFile.writeBytes(Base64.getDecoder().decode(ks))
                }
                storeFile = ksFile
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: "android"
                keyAlias = System.getenv("KEY_ALIAS") ?: "debug-key"
                keyPassword = System.getenv("KEY_PASSWORD") ?: "android"
            }
        }
    }

    defaultConfig {
        applicationId = "app.glaze.flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val envFile = rootProject.file("../../.env")
        val dropboxAppKey = if (envFile.exists()) {
            envFile.readLines()
                .find { it.startsWith("DROPBOX_APP_KEY=") }
                ?.substringAfter("=")?.trim() ?: ""
        } else ""
        val dropboxScheme = if (dropboxAppKey.isNotEmpty()) "db-$dropboxAppKey" else "db-unknown"
        manifestPlaceholders["dropboxScheme"] = dropboxScheme
    }

    buildTypes {
        debug {
            signingConfig = if (System.getenv("KEYSTORE_BASE64") != null) {
                signingConfigs.getByName("ci")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        release {
            signingConfig = if (System.getenv("KEYSTORE_BASE64") != null) {
                signingConfigs.getByName("ci")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
