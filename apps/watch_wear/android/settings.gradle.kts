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
    id("com.android.application") version "9.4.0" apply false
    // Pinned below CodeQL's Kotlin extractor ceiling: past it the
    // codeql-kotlin Security job fails outright rather than scanning less.
    // The ceiling is now 2.4.20 and this pin is 2.3.21, so it is tighter
    // than it has to be — deliberately, since these move with the
    // compose-compiler plugin against AGP 9. See decisions § 1672 and
    // apps/watch_wear/CLAUDE.md § Dependency versions.
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.21" apply false
}

rootProject.name = "watch_wear"
include(":app")
