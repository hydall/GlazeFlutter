import java.io.File
import java.security.KeyStore
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── CI signing key ────────────────────────────────────────────────────────────
// Release builds are signed with a shared key that CI passes in as a
// base64-encoded keystore (KEYSTORE_BASE64, from the DEBUG_KEYSTORE_BASE64
// secret). Absence of the secret must fall back to local debug signing.
//
// "Absence" means *blank*, not null: GitHub Actions still defines an `env:`
// entry whose secret is unset, injecting an empty string. A plain null check
// therefore took the CI branch anyway, decoded "" to zero bytes and wrote an
// empty debug-key.keystore, which AGP later rejected while packaging with
// "KeytoolException: Failed to read key debug-key from store ...:
// Tag number over 30 is not supported" (the JDK's error for a 0-byte keystore).

// Decoding is not proof of a usable key: the MIME decoder silently drops
// characters outside the base64 alphabet, so a mangled secret yields plausible
// garbage. Opening the keystore here reports the real problem at configuration
// time instead of eight minutes later, as DER-parser noise from
// :app:packageRelease.
fun verifySigningKeystore(
    keystore: File,
    storePassword: String,
    keyAlias: String,
    keyPassword: String,
) {
    val store = KeyStore.getInstance(KeyStore.getDefaultType())
    try {
        keystore.inputStream().use { store.load(it, storePassword.toCharArray()) }
    } catch (e: Exception) {
        throw GradleException(
            "KEYSTORE_BASE64 did not decode to a keystore that opens with KEYSTORE_PASSWORD: " +
                "${e.message ?: e.toString()}. Re-create the secret with: base64 -w0 debug-key.keystore",
            e,
        )
    }
    if (!store.containsAlias(keyAlias)) {
        val aliases = store.aliases().toList().joinToString().ifEmpty { "(none)" }
        throw GradleException(
            "The keystore from KEYSTORE_BASE64 has no key aliased '$keyAlias' — it holds: $aliases. " +
                "Set KEY_ALIAS to one of those.",
        )
    }
    try {
        store.getKey(keyAlias, keyPassword.toCharArray())
    } catch (e: Exception) {
        throw GradleException(
            "The key '$keyAlias' cannot be unlocked with KEY_PASSWORD: ${e.message ?: e.toString()}",
            e,
        )
    }
}

val ciKeystoreBase64: String? = System.getenv("KEYSTORE_BASE64")?.takeIf { it.isNotBlank() }

// Blank values are treated as unset here too, for the same reason as
// KEYSTORE_BASE64 above.
val ciStorePassword: String = System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() } ?: "android"
val ciKeyAlias: String = System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() } ?: "debug-key"
val ciKeyPassword: String = System.getenv("KEY_PASSWORD")?.takeIf { it.isNotBlank() } ?: "android"

val ciKeystoreFile: File? =
    ciKeystoreBase64?.let { encoded ->
        // `base64` without -w0 wraps at 76 columns and secrets often carry a
        // trailing newline; the strict decoder rejects both, the MIME one skips
        // whitespace.
        val bytes =
            try {
                Base64.getMimeDecoder().decode(encoded)
            } catch (e: IllegalArgumentException) {
                throw GradleException(
                    "KEYSTORE_BASE64 is set but is not valid base64 (${e.message}). " +
                        "Regenerate the secret with: base64 -w0 debug-key.keystore",
                )
            }
        if (bytes.isEmpty()) {
            throw GradleException(
                "KEYSTORE_BASE64 decoded to 0 bytes. Re-upload the keystore secret, " +
                    "or leave it unset to fall back to debug signing.",
            )
        }
        // Always rewritten: a truncated or stale file left by an earlier run must
        // never be silently reused as the signing key.
        rootProject.file("debug-key.keystore").apply { writeBytes(bytes) }
    }?.also { verifySigningKeystore(it, ciStorePassword, ciKeyAlias, ciKeyPassword) }

if (ciKeystoreFile == null) {
    logger.lifecycle(
        "Android signing: KEYSTORE_BASE64 is not set — signing with the local debug key. " +
            "Builds signed this way cannot be installed over a release-signed install.",
    )
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
        // Only declared when a usable keystore exists, so a half-configured "ci"
        // config can never be selected by a build type.
        if (ciKeystoreFile != null) {
            create("ci") {
                storeFile = ciKeystoreFile
                storePassword = ciStorePassword
                keyAlias = ciKeyAlias
                keyPassword = ciKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "app.glaze.flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        // Resolved once so debug and release can never disagree about which
        // config exists.
        val activeSigningConfig =
            signingConfigs.getByName(if (ciKeystoreFile != null) "ci" else "debug")

        debug {
            signingConfig = activeSigningConfig
        }
        release {
            signingConfig = activeSigningConfig
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
