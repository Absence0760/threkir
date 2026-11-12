pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Held on AGP 8.x. AGP 9 enables built-in Kotlin and rejects modules that
    // apply KGP, so the Flutter tool writes `android.builtInKotlin=false` +
    // `android.newDsl=false` to keep the legacy path alive for the plugins that
    // haven't migrated — but file_picker 11.x drops KGP when it detects AGP >= 9
    // and expects built-in Kotlin, so its Kotlin never compiles and the app fails
    // with "cannot find symbol FilePickerPlugin" (PR #563, run 29721601600).
    // Flutter's own AGP 9 tracking issue (flutter/flutter#181557) is still open.
    // Bump only with the matching Dependabot ignore in .github/dependabot.yml.
    id("com.android.application") version "8.13.2" apply false
    // Held below CodeQL 2.27.0's Kotlin ceiling. Its extractor refuses a
    // newer compiler outright — "Kotlin version 2.4.20 is too recent. CodeQL
    // currently supports versions below 2.4.20" — and it refuses from inside
    // a plugin subproject's `compileDebugKotlin`, so the whole
    // `codeql-kotlin` build fails and this host goes unscanned rather than
    // partially scanned. `apps/watch_wear/android` carries the same pin for
    // the same reason. Bump only when the bundle the pinned
    // `github/codeql-action` SHA ships raises the ceiling, together with the
    // matching Dependabot ignore in .github/dependabot.yml.
    id("org.jetbrains.kotlin.android") version "2.4.10" apply false
    // Turns `app/google-services.json` into the string resources firebase_core
    // reads when `Firebase.initializeApp()` runs with no explicit options. The
    // app module applies it only when that file is present (see
    // app/build.gradle.kts) — the file is gitignored, so an unconditional
    // apply would break every build that has not fetched it.
    id("com.google.gms.google-services") version "4.5.0" apply false
}

include(":app")
