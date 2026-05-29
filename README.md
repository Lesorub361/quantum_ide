# QuantumIDE

QuantumIDE is a next-generation AI-powered mobile IDE for web development, built with Flutter.

## Features

- **AI-powered**: Integrated Gemini AI for code suggestions and chat.
- **Terminal**: Built-in PTY terminal with Ubuntu 24.04 support.
- **Editor**: Modern code editor with syntax highlighting and autocomplete.
- **Multi-platform**: Built with Flutter for high performance.
- **Built-in ARM64 Support**: Automatic configuration of Android SDK/NDK for ARM64 Linux environments.

## ARM64 Linux Support

QuantumIDE now automatically detects and configures itself for ARM64 Linux environments.

### Automatic Fixes
- **SDK Symlinking**: Automatically redirects x86_64 SDK binaries to native ARM64 tools.
- **Project Patching**: Automatically updates Android Gradle Plugin (AGP) and fixes `gradle.properties` for projects.
- **Environment**: Pre-configured with necessary environment variables and helpful aliases.

### One-Click Setup
If some build tools are missing, you can use the **Fix Environment (Wrench icon)** button in the Editor's Environment section to automatically install all required system packages (`adb`, `clang`, `cmake`, etc.).

## Getting Started

1. Clone the repository.
2. Run `flutter pub get`.
3. Run `flutter run`.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
