# QuantumIDE Build & Development Guide

This guide covers building QuantumIDE on both Linux desktop and Android devices.

## System Requirements

### Linux Desktop
- **OS**: Ubuntu 22.04 LTS or later (or equivalent Fedora/openSUSE)
- **RAM**: 8GB minimum, 16GB recommended
- **Disk Space**: 20GB for Flutter SDK + dependencies
- **Dependencies**:
  ```bash
  sudo apt-get update
  sudo apt-get install -y \
    build-essential cmake git curl \
    libgl1-mesa-dev libxrender-dev libxrandr-dev \
    libglib2.0-dev pkg-config
  ```

### Android
- **JDK**: Java 11 or higher
  ```bash
  sudo apt-get install -y openjdk-17-jdk
  ```
- **Android SDK**: API level 26+ (minSdk requirement for flterm)
- **NDK**: For native compilation (optional, but required for some plugins)
- **Device**: Physical phone or emulator with Android 8.0+ (API 26+)

## Flutter Setup

1. **Install Flutter** (if not already installed):
   ```bash
   git clone https://github.com/flutter/flutter.git -b stable
   export PATH="$PATH:$HOME/flutter/bin"
   ```

2. **Get Flutter Doctor Status**:
   ```bash
   flutter doctor -v
   ```

3. **Install Dependencies**:
   ```bash
   cd quantum_ide
   flutter pub get
   ```

## Building

### Using the Build Script

The `build.sh` script automates the entire build process:

```bash
# Make script executable
chmod +x build.sh

# Build for Linux (debug)
./build.sh debug linux

# Build for Android (release)
./build.sh release android

# Build for all platforms (debug)
./build.sh debug all

# Build Android App Bundle for Play Store
./build.sh release android-aab
```

### Manual Building

#### Linux Desktop

```bash
# Debug build
flutter build linux --debug

# Release build
flutter build linux --release

# Run directly
flutter run -d linux --debug
```

**Output locations**:
- Debug: `build/linux/x64/debug/bundle/`
- Release: `build/linux/x64/release/bundle/`

#### Android APK

```bash
# Debug APK
flutter build apk --debug

# Release APK (requires signing configured)
flutter build apk --release

# Install to connected device
flutter install

# Run on device
flutter run --debug -d <device-id>
```

**Output locations**:
- Debug: `build/app/outputs/apk/debug/app-debug.apk`
- Release: `build/app/outputs/apk/release/app-release.apk`

**Generate Release Keystore** (one-time setup):

```bash
keytool -genkey -v -keystore ~/quantum_ide_keystore.jks \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias quantum_ide_key

# Then update android/key.properties:
storeFile=~/quantum_ide_keystore.jks
keyAlias=quantum_ide_key
keyPassword=<your-password>
storePassword=<your-password>
```

#### Android App Bundle (for Play Store)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

## Common Issues & Solutions

### Issue: "AAPT2 error"
**Solution**:
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

### Issue: "Gradle: Command not found"
**Solution**:
```bash
export PATH="$PATH:$ANDROID_SDK_ROOT/tools/bin"
flutter doctor --android-licenses  # Accept all licenses
```

### Issue: "Java version mismatch"
**Solution**:
```bash
# Verify Java version
java -version

# Should be 11+. If not:
sudo update-alternatives --config java
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

### Issue: "No Android devices found"
**Solution**:
```bash
# List all devices
adb devices -l

# Start emulator
emulator -avd Pixel_4_API_30

# Restart ADB if needed
adb kill-server
adb start-server
```

### Issue: "NDK not found" (if building native code)
**Solution**:
```bash
# Download NDK via Android Studio or:
export ANDROID_NDK_ROOT=$ANDROID_SDK_ROOT/ndk/25.2.9519653
export PATH="$PATH:$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
```

### Issue: "Build fails on ARM64 Linux"
**Solution**: The project includes ARM64-specific configurations:
```bash
# The build system will auto-detect and use proper symlinks
# Ensure you have flutter_pty build dependencies:
sudo apt-get install -y libffi-dev libutil-linux-dev
```

## Environment Variables

```bash
# Android
export ANDROID_SDK_ROOT="$HOME/Android/sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Flutter (optional, if Flutter isn't in PATH)
export PATH="$PATH:$HOME/flutter/bin"

# Add to ~/.bashrc or ~/.zshrc for persistence
```

## Development Workflow

### Hot Reload
```bash
flutter run --debug
# Press 'r' to reload code changes
# Press 'R' to restart the app
```

### Debugging
```bash
# With DevTools
flutter run --debug --enable-devtools

# View logs
flutter logs
```

### Testing
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/widget_test.dart
```

## Code Analysis

```bash
# Analyze code
dartanalyzer lib/

# Format code
dart format lib/ test/

# Get analysis results with build_runner
flutter pub run build_runner build
```

## Troubleshooting Build Failures

1. **Check build logs**:
   ```bash
   cat build.log
   ```

2. **Clean build cache**:
   ```bash
   flutter clean
   rm -rf build/
   flutter pub get
   ```

3. **Check Flutter doctor**:
   ```bash
   flutter doctor -v
   ```

4. **Verify Android setup**:
   ```bash
   flutter doctor --android-licenses
   ```

5. **Check git status** (for module conflicts):
   ```bash
   git status
   git clean -fd
   ```

## Performance Tips

### Linux Desktop Build
- Use Release mode for production: `./build.sh release linux`
- The release build is ~10x faster after first build

### Android Build
- First build takes ~5-10 minutes
- Use `--fast-start` for incremental builds
- Debug APK is smaller and faster: `flutter build apk --debug`

## Signing & Distribution

### Android Play Store
1. Create release keystore (see above)
2. Build app bundle: `./build.sh release android-aab`
3. Upload to Play Console

### Linux Desktop
- Binary in `build/linux/x64/release/bundle/quantum_ide`
- Create AppImage or Snap for distribution

## Support & Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Android Documentation](https://developer.android.com/)
- [Project README](./README.md)
- [Architecture Analysis](./quantum_ide_analysis.md)

---

**Last Updated**: May 2026  
**Tested On**: Ubuntu 24.04 LTS, Android 8.0+
