plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fetchtube.fetchtube"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.fetchtube.fetchtube"
        // 29 is the floor for MediaStore RELATIVE_PATH, which is how downloads reach
        // Download/FetchTube without legacy storage permissions. (Library floor is 24.)
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Each ABI carries its own python+ffmpeg payload (~30MB), so release builds must be
    // split: `flutter build apk --split-per-abi`. Flutter's plugin owns abiFilters —
    // setting them here (or an android.splits block) conflicts with it.

    packaging.jniLibs {
        // yt-dlp/ffmpeg are exec'd as real files, so the payloads must be extracted, not mmap'd.
        useLegacyPackaging = true
        // These are zip archives wearing a .so name; llvm-strip chokes on them.
        keepDebugSymbols += setOf("**/libpython.zip.so", "**/libffmpeg.zip.so")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("androidx.core:core-ktx:1.17.0")
}

flutter {
    source = "../.."
}
