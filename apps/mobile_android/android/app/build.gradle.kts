plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// FCM registration needs the google-services plugin: it reads
// `google-services.json` and generates the `google_app_id` /
// `gcm_defaultSenderId` / `project_id` string resources that firebase_core
// loads for the default app. Without it the file is inert and
// `Firebase.initializeApp()` throws, which `FirebasePushMessaging` catches —
// so the whole push path no-ops in silence rather than failing at build time.
//
// The file is gitignored (see the repo-root .gitignore) and the release
// workflow decodes it from GOOGLE_SERVICES_JSON_BASE64, so it is absent on a
// fresh clone. Applying the plugin conditionally keeps `flutter run` working
// there; the trade-off is that a release build missing the secret still
// succeeds, and registers no token. `release-android.yml` warns in that case.
//
// The Firebase console's "Add Firebase SDK" step does not apply to this module
// and following it breaks two things. Its `plugins { id(...) }` form cannot be
// made conditional, so a fresh clone would fail to configure; and its Firebase
// BoM + `implementation(...)` block would pull the Android artifacts a second
// time, beside the ones firebase_core / firebase_messaging already contribute
// through Flutter's plugin mechanism. The console cannot tell this is a Flutter
// app. The version pin lives in settings.gradle.kts.
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "google-services.json absent — skipping the google-services plugin. " +
            "This build will not receive push notifications.",
    )
}

val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreProperties.load(FileInputStream(keystoreFile))
}

android {
    namespace = "com.threkir.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Kotlin 2.3+ removed the `kotlinOptions { jvmTarget = ... }` DSL.
    // Migrate to the `compilerOptions` block on the kotlin extension.
    // https://kotl.in/u1r8ln
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.threkir.app"
        minSdk = 26
        // Play Console requires targetSdk >= 36 (Android 16) for new +
        // updated apps from 2026-08-31 (one year behind the latest
        // Android release). Pinning the value here so we don't silently
        // regress if Flutter SDK ships with an older default. watch_wear
        // stays on its own pin — Wear OS is exempt from the annual
        // target-API requirement (its floor is API 30).
        // targetSdk 36 behaviour changes to re-verify on-device are
        // listed in deployment.md § targetSdk 36.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreFile.exists()) {
                signingConfigs.getByName("release")
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
    // Wearable Data Layer — pushes the Supabase session to the paired watch_wear app.
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    // NotificationCompat / NotificationManagerCompat used by
    // RunNotificationBridge live under androidx.core:core, which geolocator
    // already pulls in transitively at 1.16.0 — no explicit dep needed.

    // Health Connect client, for HealthRoutePermissionBridge's
    // READ_EXERCISE_ROUTES request. The `health` plugin depends on the same
    // artifact, but as `implementation`, which keeps it off our compile
    // classpath. Keep this version in lockstep with the plugin's
    // (health-13.3.1/android/build.gradle) — two versions on one runtime
    // classpath is a Gradle conflict resolution away from a surprise.
    implementation("androidx.health.connect:connect-client:1.2.0-alpha02")

    // JUnit for pure-JVM unit tests on the native Kotlin bridges
    // (WearRoutesBridge / WearAuthBridge / RunNotificationBridge).
    // The bridges' platform-channel + Wearable Data Layer surfaces
    // can't run on a host JVM, but the arg-parsing + DataMap-field
    // construction logic is extracted into pure helpers that we
    // test here. Mirrors the watch_wear test surface convention.
    testImplementation("junit:junit:4.13.2")
}
