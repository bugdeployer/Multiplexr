import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val releaseSigning = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested && !signingFile.exists()) {
    throw GradleException("Release signing is not configured. Create android/key.properties as described in CONTRIBUTING.md.")
}

android {
    namespace = "com.bugdeployer.multiplexr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bugdeployer.multiplexr"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Keep the Android build number monotonic across public releases.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["pluginSandboxEnabled"] = "false"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        externalNativeBuild { cmake { arguments += "-DANDROID_STL=none" } }
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                storeFile = rootProject.file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        debug {
            manifestPlaceholders["pluginSandboxEnabled"] = providers.gradleProperty("pluginSandboxProof").orNull == "true"
        }
        release {
            if (signingFile.exists()) signingConfig = signingConfigs.getByName("release")
        }
    }
}

android.externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("junit:junit:4.13.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    implementation("androidx.media3:media3-exoplayer:1.9.2")
    implementation("androidx.media3:media3-ui:1.9.2")
    implementation("androidx.media3:media3-session:1.9.2")
}
