# Changelog

## 1.2.232
- **Ubuntu 24.04 `/lib -> usr/lib` Auto-Repair & `GLIBC_2.38` Mismatch Recovery**:
  - Updated [`isGuestLibcBroken`](lib/core/services/runtime_service.dart) and [`_repairGuestLibcIfBroken`](lib/core/services/runtime_service.dart) to detect BOTH missing `/lib` (`execve("/usr/bin/bash"): Function not implemented`, `basename: required file not found`) AND broken `/lib` directories downgraded to Ubuntu 20.04 `glibc 2.31` on Ubuntu 24.04 (`libc.so.6: version 'GLIBC_2.38' not found`). Restores `/lib -> usr/lib` + `usr/lib/ld-linux-aarch64.so.1` purely in Dart (without shelling out to `cp`), strips `2.31` leftovers, and blocks downloading `libc6_2.31` onto Ubuntu 24.04.
  - Updated [`_generateQuantumHealX64Script`](lib/core/services/runtime_service.dart) (`quantum-heal-x64`, used by `flutter-release-engine`, `flutter-release-fix`, and `build-fix`) to extract `libc6:amd64` `.deb` archives into a temporary staging directory instead of `/` and prefer Ubuntu 24.04 `libc6_2.39` first, preventing `dpkg -x` from overwriting `/lib -> usr/lib`.
- **Clean `flutter()` Gradle Config Wrapper (`BASHRC_VERSION=33`)**:
  - Updated [`RuntimeService`](lib/core/services/runtime_service.dart) `.bashrc` and `.zshrc` `flutter()` wrappers to create `/root/.gradle` alongside `~/.gradle` and verify `[ -d "$(dirname "$gp")" ]` and `[ -w "$gp" ]` before writing `gradle.properties`, eliminating `bash: /root/.gradle/gradle.properties: No such file or directory` stderr spam.
- **Antigravity CLI (`agy`) Flag Compatibility**:
  - Removed the injected `--settings '{"enableTerminalSandbox":false}'` flag from `.bashrc`/`.zshrc` `agy()` wrappers and [`CliAuthService`](lib/core/services/cli_auth_service.dart) (`flags provided but not defined: -settings`).

## 1.2.231
- **Ubuntu 24.04 Migration & Rootfs Cleanup (`EACCES` / `errno = 13` Fix)**:
  - Added [`_forceDeleteDirectory`](lib/core/services/runtime_service.dart) (`chmod -R u+rwX` + `rm -rf` with non-symlink-following Dart fallback) for `migrateToUbuntu2404()`, `reset()`, and `preserved_home` cleanup.
  - Updated Android [`BootstrapManager.deleteRecursively`](android/app/src/main/kotlin/com/example/quantum_ide/BootstrapManager.kt) to avoid following symlinks (`Os.lstat` / `S_ISLNK`) and restore owner permissions (`Os.chmod`) prior to deletion.
  - Preserved symlinks and avoided `followLinks: true` when backing up/restoring `/root` files during migration.
- **CodeCrafter Editor Blank/Gray Screen Fix**:
  - Fixed `CodeCrafterController` throwing on `null` language IDs (`pubspec.lock`, `gradle.properties`, plain-text files) which triggered release `RenderErrorBox(0xF0C0C0C0)` while keeping only the line-number gutter visible.
  - Cleared stale `_langId` on switching to plain-text files, added parser/bounds guards across `buildTextSpan`, `Gutter`, and `CodeArea`, replaced `double.maxFinite` / negative widths and empty `ThemeData()`, and wired proper `didUpdateWidget` / `dispose` cleanup.
  - Extended `CodeCrafterEditorWrapper._resolveLanguage` for `pubspec.lock`, `podfile.lock`, `Dockerfile`, `Makefile`, `.properties`, `.gradle`/`.groovy`, `.ini`/`.cfg`/`.conf`/`.toml`/`.env`, `.arb`, and `.plist`.
- **PRoot Terminal TLS / `x509` Certificate Verification Fix**:
  - Added `_repairCaCertificatesIfNeeded()` in `RuntimeService.init()` to merge guest Mozilla CAs with Android host system/user CA certificates (`/apex/com.android.conscrypt/cacerts`, `/system/etc/security/cacerts`, `/data/misc/user/0/cacerts-added`) into `/etc/ssl/certs/ca-certificates.crt`.
  - Exported `SSL_CERT_FILE`, `SSL_CERT_DIR`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, and `GIT_SSL_CAINFO` across `.bashrc` (`BASHRC_VERSION=32`), `init-host`, `RuntimeService.env`, and Android `ProcessManager`.

## 1.2.230
- **CodeCrafter LSP Bridge (`LspBridgeConfig`)**: connected QuantumIDE's shared `LspService` to `CodeCrafter` for live red/yellow error underlines (`publishDiagnostics`), LSP autocomplete with symbol icons, and hover documentation popups without spawning duplicate LSP processes.
- **Word Autocomplete Fallback**: improved word-based suggestions when LSP is not ready or unavailable (case-insensitive matching, proper cursor prefix filtering).

## 1.2.229
- **Autocomplete Overlay & Theme Consistency**: styled `SuggestionStyle` and `HoverDetailsStyle` in `CodeCrafterEditorWrapper` to match the active palette, removed hardcoded dark backgrounds in `Breadcrumbs` and AI chat code blocks.
- **Runtime Stability Fixes**:
  - Fixed `Bad state: Cannot use "ref" after the widget was disposed` in `StableEditorWidgetState.dispose`.
  - Handled HTTP `402`/`401` errors in `flutter_code_crafter` AI inline completion with a 5-minute cooldown instead of uncaught async exceptions.
  - Guarded `/root/android-sdk` permission checks (`PathAccessException`) in `PackageService` on desktop Linux.
  - Caught missing binary `ProcessException` errors during `McpService` auto-connect.

## 1.2.226 – 1.2.228
- Enabled `CodeCrafter` as the default editor with `allLanguages` syntax highlighting and adaptive `editorTheme`.
- Added explicit `GptMarkdownStyleSheet` styling in Roxum Chat for headings, inline code, tables, and links.
- Split Roxum Chat code-block actions into terminal execution vs editor insertion, and added anti-hallucination tool guards in `RoxumAiClient`.

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
