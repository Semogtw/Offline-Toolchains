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
    offlineExactArtifacts("org.jetbrains.kotlin:kotlin-stdlib-common:2.0.21")
    offlineExactArtifacts("androidx.activity:activity-compose:1.8.2")
    offlineExactArtifacts("androidx.activity:activity-ktx:1.7.0")
    offlineExactArtifacts("androidx.core:core:1.13.1")
    offlineExactArtifacts("androidx.core:core-ktx:1.5.0")
    offlineExactArtifacts("androidx.tracing:tracing:1.0.0")
}

val hydrateOfflineExactArtifacts = tasks.register("hydrateOfflineExactArtifacts") {
    inputs.files(offlineExactArtifacts)
    doLast {
        offlineExactArtifacts.files.forEach { file ->
            check(file.isFile) { "Missing offline artifact: ${file.name}" }
        }
    }
}

gradle.projectsEvaluated {
    project(":app").tasks.named("preBuild") {
        dependsOn(hydrateOfflineExactArtifacts)
    }
}
