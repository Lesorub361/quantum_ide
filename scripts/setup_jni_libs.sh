#!/bin/bash

# Script to copy JNI libraries from openfang to quantum_ide
# Run this from the root of quantum_ide project

SOURCE_PATH1="/home/lesorub/Загрузки/openfang-termux-main/flutter_app/android/app/jniLibs"
SOURCE_PATH2="/home/lesorub/Загрузки/openfang-termux-main/flutter_app/android/app/src/main/jniLibs"
SOURCE_PATH3="/home/lesorub/Загрузки/openfang_ide/android/app/src/main/jniLibs"
TARGET_PATH="/home/lesorub/Загрузки/quantum_ide/android/app/src/main/jniLibs"

mkdir -p "$TARGET_PATH"

for SRC in "$SOURCE_PATH1" "$SOURCE_PATH2" "$SOURCE_PATH3"; do
    if [ -d "$SRC" ]; then
        echo "Copying from $SRC..."
        cp -r "$SRC"/* "$TARGET_PATH/"
    fi
done

echo "Done! JNI libraries have been set up."
