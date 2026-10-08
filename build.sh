#!/bin/bash

# QuantumIDE Multi-Platform Build Script
# Supports: Linux Desktop, Android Phone, and cross-platform testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_LOG="$PROJECT_ROOT/build.log"
FLUTTER_BUILD_MODE="${1:-release}"
TARGET_PLATFORM="${2:-all}"

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp]${NC} ${level}: ${message}" | tee -a "$BUILD_LOG"
}

error() {
    echo -e "${RED}[ERROR]${NC} $@" | tee -a "$BUILD_LOG"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@" | tee -a "$BUILD_LOG"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@" | tee -a "$BUILD_LOG"
}

# Clear build log
> "$BUILD_LOG"

log "INFO" "QuantumIDE Build Script Started"
log "INFO" "Project Root: $PROJECT_ROOT"
log "INFO" "Build Mode: $FLUTTER_BUILD_MODE"
log "INFO" "Target Platform: $TARGET_PLATFORM"

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    if ! command -v flutter &> /dev/null; then
        error "Flutter is not installed. Please install Flutter SDK."
    fi
    
    if ! command -v java &> /dev/null; then
        error "Java is not installed. Please install JDK 11 or higher."
    fi
    
    local java_version=$(java -version 2>&1 | grep -oP 'version "\K[0-9]+' | head -1)
    if [[ $java_version -lt 11 ]]; then
        error "Java version must be 11 or higher. Current: $java_version"
    fi
    
    log "INFO" "Flutter version: $(flutter --version | head -1)"
    log "INFO" "Dart version: $(dart --version | head -1)"
    log "INFO" "Java version: $java_version"
    success "All prerequisites met"
}

# Function to setup dependencies
setup_dependencies() {
    log "INFO" "Setting up dependencies..."
    cd "$PROJECT_ROOT"
    
    flutter pub get 2>&1 | tee -a "$BUILD_LOG"
    success "Dependencies installed"
}

# Function to run analyzer
run_analyzer() {
    log "INFO" "Running Dart analyzer..."
    cd "$PROJECT_ROOT"
    
    flutter analyze --fatal-infos 2>&1 | tee -a "$BUILD_LOG" || warning "Analyzer found issues but continuing..."
}

# Function to run tests
run_tests() {
    log "INFO" "Running tests..."
    cd "$PROJECT_ROOT"
    
    if [[ -d "test" ]]; then
        flutter test 2>&1 | tee -a "$BUILD_LOG" || warning "Some tests failed"
    else
        warning "No test directory found"
    fi
}

# Function to build Linux
build_linux() {
    log "INFO" "Building for Linux..."
    cd "$PROJECT_ROOT"
    
    flutter build linux --$FLUTTER_BUILD_MODE 2>&1 | tee -a "$BUILD_LOG" || {
        error "Linux build failed. Check logs above."
    }
    
    local output_path="$PROJECT_ROOT/build/linux/x64/release/bundle"
    if [[ ! -d "$output_path" ]]; then
        output_path="$PROJECT_ROOT/build/linux/x64/debug/bundle"
    fi
    
    success "Linux build complete: $output_path"
}

# Function to build Android APK
build_android_apk() {
    log "INFO" "Building Android APK (${FLUTTER_BUILD_MODE})..."
    cd "$PROJECT_ROOT"
    
    # Ensure Android SDK is configured
    if [[ ! -d "$ANDROID_SDK_ROOT" ]]; then
        warning "ANDROID_SDK_ROOT not set or invalid, attempting to auto-detect..."
        if [[ -d "$HOME/Android/Sdk" ]]; then
            export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
        elif [[ -d "$HOME/Android/sdk" ]]; then
            export ANDROID_SDK_ROOT="$HOME/Android/sdk"
        elif [[ -d "/usr/lib/android-sdk" ]]; then
            export ANDROID_SDK_ROOT="/usr/lib/android-sdk"
        else
            error "Android SDK not found. Please set ANDROID_SDK_ROOT or install Android Studio."
        fi
    fi
    
    log "INFO" "Using Android SDK: $ANDROID_SDK_ROOT"
    
    # Build APK
    if [[ "$FLUTTER_BUILD_MODE" == "release" ]]; then
        flutter build apk --release --no-tree-shake-icons 2>&1 | tee -a "$BUILD_LOG" || {
            error "Android APK release build failed"
        }
    else
        flutter build apk --debug 2>&1 | tee -a "$BUILD_LOG" || {
            error "Android APK debug build failed"
        }
    fi
    local apk_path="$PROJECT_ROOT/build/app/outputs/apk/${FLUTTER_BUILD_MODE}/app-${FLUTTER_BUILD_MODE}.apk"
    if [[ ! -f "$apk_path" ]]; then
        apk_path="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-${FLUTTER_BUILD_MODE}.apk"
    fi

    if [[ -f "$apk_path" ]]; then
        success "Android APK build complete: $apk_path"
        log "INFO" "APK Size: $(du -h "$apk_path" | cut -f1)"
    else
        error "APK not found at expected path: $apk_path"
    fi
}

# Function to build Android App Bundle
build_android_aab() {
    log "INFO" "Building Android App Bundle (release)..."
    cd "$PROJECT_ROOT"
    
    flutter build appbundle --release 2>&1 | tee -a "$BUILD_LOG" || {
        error "Android App Bundle build failed"
    }
    
    local aab_path="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
    if [[ -f "$aab_path" ]]; then
        success "Android App Bundle build complete: $aab_path"
    else
        error "App Bundle not found"
    fi
}

# Function to run on Android device
run_on_android() {
    log "INFO" "Deploying to Android device..."
    cd "$PROJECT_ROOT"
    
    if ! command -v adb &> /dev/null; then
        error "adb not found. Please ensure Android SDK is properly installed."
    fi
    
    local devices=$(adb devices -l | grep -v 'List of' | wc -l)
    if [[ $devices -lt 2 ]]; then
        error "No Android devices found. Please connect a device or start an emulator."
    fi
    
    flutter run --$FLUTTER_BUILD_MODE 2>&1 | tee -a "$BUILD_LOG"
    success "App deployed to Android device"
}

# Function to run on Linux desktop
run_on_linux() {
    log "INFO" "Running on Linux desktop..."
    cd "$PROJECT_ROOT"
    
    flutter run -d linux --$FLUTTER_BUILD_MODE 2>&1 | tee -a "$BUILD_LOG"
}

# Main build logic
main() {
    check_prerequisites
    setup_dependencies
    run_analyzer
    run_tests
    
    case "$TARGET_PLATFORM" in
        linux)
            build_linux
            ;;
        android)
            build_android_apk
            ;;
        android-aab)
            build_android_aab
            ;;
        all)
            build_linux
            build_android_apk
            ;;
        *)
            error "Unknown platform: $TARGET_PLATFORM. Choose: linux, android, android-aab, all"
            ;;
    esac
    
    log "INFO" "Build completed successfully!"
    log "INFO" "Full build log: $BUILD_LOG"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [BUILD_MODE] [PLATFORM]

Build Modes:
  release     - Build optimized release version (default)
  debug       - Build with debug symbols
  profile     - Build with profiling enabled

Platforms:
  linux       - Build for Linux desktop
  android     - Build Android APK
  android-aab - Build Android App Bundle
  all         - Build for all platforms (default)

Examples:
  ./build.sh debug linux          # Debug build for Linux
  ./build.sh release android      # Release Android APK
  ./build.sh debug all            # Debug build for all platforms
EOF
}

# Handle help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

main
