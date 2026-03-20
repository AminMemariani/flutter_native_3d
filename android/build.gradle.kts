group = "com.flutternative3d.flutter_native_3d"
version = "0.1.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.7.3")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply(plugin = "com.android.library")
apply(plugin = "kotlin-android")

val androidExtension = extensions.getByType<com.android.build.gradle.LibraryExtension>()

androidExtension.apply {
    namespace = "com.flutternative3d.flutter_native_3d"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            kotlin.srcDirs("src/main/kotlin")
        }
    }
}

dependencies {
    // SceneView wraps Google's Filament renderer with a high-level Android View API.
    // Provides: glTF loading, PBR rendering, camera orbit, animation playback.
    // If SceneView becomes unmaintained, migrate to raw Filament (com.google.android.filament:*)
    // behind the SceneManager/ModelLoader abstraction. Dart API stays unchanged.
    implementation("io.github.sceneview:sceneview:2.2.1")
}
