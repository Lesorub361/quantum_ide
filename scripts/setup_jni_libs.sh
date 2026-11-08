#!/usr/bin/env bash
set -e

# Script to set up and verify JNI libraries for QuantumIDE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_PATH="${TARGET_PATH:-$PROJECT_ROOT/android/app/src/main/jniLibs}"

mkdir -p "$TARGET_PATH"

CANDIDATES=(
    "${JNI_SOURCE_DIR:-}"
    "$PROJECT_ROOT/../openfang-termux-main/flutter_app/android/app/jniLibs"
    "$PROJECT_ROOT/../openfang-termux-main/flutter_app/android/app/src/main/jniLibs"
    "$PROJECT_ROOT/../openfang_ide/android/app/src/main/jniLibs"
    "$HOME/Downloads/openfang-termux-main/flutter_app/android/app/src/main/jniLibs"
    "$HOME/Загрузки/openfang-termux-main/flutter_app/android/app/src/main/jniLibs"
)

COPIED=0
for SRC in "${CANDIDATES[@]}"; do
    if [ -n "$SRC" ] && [ -d "$SRC" ]; then
        echo "Copying JNI libraries from $SRC -> $TARGET_PATH..."
        cp -r "$SRC"/* "$TARGET_PATH/"
        COPIED=1
    fi
done

SO_COUNT=$(find "$TARGET_PATH" -name "*.so" 2>/dev/null | wc -l | tr -d ' ')
if [ "$SO_COUNT" -gt 0 ]; then
    echo "✅ Done! Verified $SO_COUNT native (.so) libraries in $TARGET_PATH."
else
    if [ "$COPIED" -eq 0 ]; then
        echo "⚠️ No external JNI source directory found and no .so files in $TARGET_PATH."
        echo "   Tip: Set JNI_SOURCE_DIR=/path/to/jniLibs before running this script."
    fi
fi
