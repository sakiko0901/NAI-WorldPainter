plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val mobilePreview = providers.gradleProperty("mobilePreview").orNull == "true"

android {
    namespace = "com.naihuishi.nai_huishi"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (mobilePreview) {
            "com.naihuishi.nai_huishi.preview"
        } else {
            "com.naihuishi.nai_huishi"
        }
        manifestPlaceholders["appLabel"] =
            if (mobilePreview) "NAI 绘世测试版" else "NAI 绘世"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 超分功能：把 jniLibs 里的可执行文件(librealsr.so/librealcugan.so)及依赖库
    // 解压到 nativeLibraryDir。Android 10+ 的 W^X 策略只允许从该目录执行 ELF，
    // 因此必须 useLegacyPackaging=true 强制解压，否则 .so 留在 APK 内无法 exec。
    // 同时排除非 arm64-v8a ABI 的预编译 .so (超分插件打包了多 ABI)
    packaging {
        jniLibs {
            useLegacyPackaging = true
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
