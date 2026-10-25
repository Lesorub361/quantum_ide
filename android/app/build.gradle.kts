import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = when {
    rootProject.file("key.properties").exists() -> rootProject.file("key.properties")
    rootProject.file("keystore.properties").exists() -> rootProject.file("keystore.properties")
    file("key.properties").exists() -> file("key.properties")
    else -> rootProject.file("key.properties")
}
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { input ->
        keystoreProperties.load(input)
    }
}

android {
    namespace = "com.example.quantum_ide"
    // Поднимаем для совместимости с новыми плагинами (требование ошибки)
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    lint {
        checkReleaseBuilds = false
        abortOnError = false
        ignoreWarnings = true
        checkDependencies = false
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.quantum_ide"
        // libghostty (flterm) требует shm_open из libc — в Bionic с Android 8 (API 26).
        minSdk = 26
        targetSdk = 36 // Современный стандарт
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // On local tablet builds, restrict to arm64-v8a to prevent corrupted 32-bit APK on Android/Xiaomi
        if (System.getenv("GITHUB_ACTIONS") != "true") {
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (storeFilePath != null) {
                val appDirFile = file(storeFilePath)
                val rootDirFile = rootProject.file(storeFilePath)
                storeFile = when {
                    appDirFile.exists() -> appDirFile
                    rootDirFile.exists() -> rootDirFile
                    else -> appDirFile
                }
            }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            val releaseSigningConfig = signingConfigs.getByName("release")
            if (releaseSigningConfig.storeFile?.exists() == true) {
                signingConfig = releaseSigningConfig
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("org.apache.commons:commons-compress:1.26.1")
    implementation("org.tukaani:xz:1.9")
    implementation("com.github.luben:zstd-jni:1.5.6-9@aar")
}
