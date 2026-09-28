pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.application") version "9.4.1" apply false
    // Pinned below CodeQL's Kotlin extractor ceiling: past it the
    // codeql-kotlin Security job fails outright rather than scanning less.
    // Bundle 2.27.0 (the pinned github/codeql-action SHA) refuses >= 2.4.20,
    // so 2.4.10 is the highest analysable release. The compose plugin's
    // module metadata requires kotlin-gradle-plugin at its own version, which
    // lifts AGP 9's built-in Kotlin (a 2.2.10 runtime floor) to this one — so
    // these two lines ARE the compiler version; move them together. See
    // decisions § 1672 and apps/watch_wear/CLAUDE.md § Dependency versions.
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.10" apply false
}

rootProject.name = "watch_wear"
include(":app")
