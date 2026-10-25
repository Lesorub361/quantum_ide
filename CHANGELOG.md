# Changelog

## 1.2.53
- Fixed Dart VM release engine crash on Redmi/Xiaomi devices by properly patching PRoot Flutter Engine snapshotter.
- Cleaned up Gradle flags to ensure seamless compatibility with GitHub Actions CI/CD builders.
- Full multi-stack build support with ready-to-build templates for Flutter, Kotlin, and Java projects.
- Integrated Box64 emulator for on-device execution of x86/x86_64 binaries.

## 1.2.52
- Performance optimizations to reduce CPU and RAM usage.
- Editor: replaced heavy `ref.watch(aiProvider)` rebuilds with targeted listeners.
- File reading optimized: binary check + `readAsString` for text files.
- AI sessions saving debounced to reduce disk IO.
- Workspace switching now properly clears old project files.
- Terminal: improved text selection behavior and copy/paste handling.
- Terminal: fixed encoding-related character display issues.
- Auto-save debounce increased and save-on-background enforced.
- Max open editor tabs limited to prevent memory growth.

## 1.2.1
- Stable release with improvements and bug fixes.
