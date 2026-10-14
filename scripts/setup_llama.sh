#!/usr/bin/env bash
set -e

# Setup script for llama.cpp dependency in local_plugins
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ANDROID_CPP_DIR="$ROOT_DIR/local_plugins/llama_flutter_android/android/src/main/cpp/llama.cpp"
IOS_CPP_DIR="$ROOT_DIR/local_plugins/llama_flutter_android/ios/llama_cpp_src"

echo "Checking llama.cpp native dependencies..."

if [ ! -d "$ANDROID_CPP_DIR" ] || [ -z "$(ls -A "$ANDROID_CPP_DIR" 2>/dev/null)" ]; then
  echo "Cloning llama.cpp for Android..."
  git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$ANDROID_CPP_DIR"
else
  echo "llama.cpp for Android is already present."
fi

if [ ! -d "$IOS_CPP_DIR" ] || [ -z "$(ls -A "$IOS_CPP_DIR" 2>/dev/null)" ]; then
  echo "Cloning llama.cpp for iOS..."
  git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$IOS_CPP_DIR"
else
  echo "llama.cpp for iOS is already present."
fi

echo "Done! Native llama.cpp dependencies are set up."
