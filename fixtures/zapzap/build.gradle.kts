plugins {
    id("com.android.application") version "8.7.3" apply false
    id("com.android.library") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.jvm") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}

val offlineExactArtifacts by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}

dependencies {
    offlineExactArtifacts("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    offlineExactArtifacts("androidx.annotation:annotation-jvm:1.8.1")
}

tasks.register("hydrateOfflineExactArtifacts") {
    inputs.files(offlineExactArtifacts)
    doLast {
        offlineExactArtifacts.files.forEach { file ->
            check(file.isFile) { "Missing offline artifact: ${file.name}" }
        }
    }
}
