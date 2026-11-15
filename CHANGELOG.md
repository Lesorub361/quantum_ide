# Changelog

## 1.2.235
- **Conduit Terminal Reflow & Pinch-to-Zoom Artifacts Fix (`conduit_vt`, `ConduitTerminalSurface`)**:
  - Fixed ghost character artifacts (`' ' : : #`, `⠋`, `⠙`, `⠸`, `□`) appearing after pinching to zoom in and out by zeroing stale cells in [`BufferLine.resize`](packages/conduit_vt/lib/src/core/buffer/line.dart) and [`_LineBuilder`](packages/conduit_vt/lib/src/core/reflow.dart), tracking cursor coordinates across `reflow()` with `CellAnchor` in [`Buffer.resize`](packages/conduit_vt/lib/src/core/buffer/buffer.dart), and triggering immediate repaints in [`RenderTerminal`](packages/conduit_vt/lib/src/ui/render.dart) and [`Terminal.resize`](packages/conduit_vt/lib/src/terminal.dart).
  - Quantized pinch-to-zoom font steps in [`ConduitTerminalSurface`](lib/features/terminal/conduit/conduit_terminal_surface.dart), removed duplicate pinch/tap wrappers in [`terminal_panel_content.dart`](lib/features/terminal/presentation/widgets/terminal_panel_content.dart), and debounced PTY resize in [`dedicated_terminal_notifier.dart`](lib/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart).
- **Multi-Line Wrapped URL Opening & Smooth Selection Handles (`Buffer`, `TerminalView`, `QuantumLinkDetector`)**:
  - Added multi-line URL stitching (`findUrlRangeAt` / `getUrlAt`) in [`Buffer`](packages/conduit_vt/lib/src/core/buffer/buffer.dart) and [`QuantumLinkDetector.findLinkInBuffer`](lib/features/terminal/engine/quantum_link_detector.dart) so tapping or long-pressing any line of a multi-line wrapped URL (including `agy` OAuth links) opens and selects the full unbroken URL without `\n` breaks.
  - Fixed selection handle dragging in [`TerminalView`](packages/conduit_vt/lib/src/terminal_view.dart) and [`RenderTerminal`](packages/conduit_vt/lib/src/ui/render.dart) with finger-offset tracking, viewport edge auto-scroll, and toolbar suppression while dragging.

## 1.2.234
- **Redesigned Professional Git UI & Workflow (`GitPanel`, `GitGraphPage`)**:
  - Replaced cluttered stacked toolbars and clipped horizontal buttons with a clean compact header, full-width segmented quick-action bar (`Sync`, `Fetch`, `Pull`, `Push`, `Stash`), overflow menu, and streamlined tabs (`Изменения`, `История`, `Ветки`, `Релизы`).
  - Upgraded **Changes** composer & file rows with clearer staging state, diff summary stats (`+N / -M`), clean working tree summary card with latest commit preview, and context actions.
  - Upgraded **Branches & Stash** manager with search bar, active `HEAD` tracking card (upstream / ahead-behind / push & graph shortcuts), expandable local & remote branch lists with one-tap Switch / Merge / Rename / Delete / Fetch / Checkout, and Stash cards (`Diff`, `Apply`, `Pop`, `Drop`).
- **Unified Git Theme & `ConduitPalette` Synchronization (`GitThemeColors`)**:
  - Added [`GitThemeColors`](lib/features/git/presentation/widgets/git_theme.dart) resolving active `ConduitPalette` when `syncAppWithTerminalPalette` is enabled and falling back to Material 3 `ColorScheme`.
  - Applied dynamic theme/background/accent colors across all Git screens and dialogs: [`GitPanel`](lib/features/git/presentation/widgets/git_panel.dart), [`GitGraphPage`](lib/features/git/presentation/pages/git_graph_page.dart), [`GitDownloadDialog`](lib/features/git/presentation/widgets/git_download_dialog.dart), [`GitDiffPage`](lib/features/git/presentation/pages/git_diff_page.dart), [`DiffViewerPage`](lib/features/git/presentation/pages/diff_viewer_page.dart), and [`GitMergeConflictPage`](lib/features/git/presentation/pages/git_merge_conflict_page.dart).

## 1.2.233
- **PRoot `localhost` DNS Fix for `agy` & Go Binaries (`/etc/hosts` + `/etc/nsswitch.conf`)**:
  - Fixed `Failed to start: listen tcp: lookup localhost on 8.8.8.8:53: no such host` when running `agy` in PRoot.
  - Added [`_writeHostsFile`](lib/core/services/runtime_service.dart) (`127.0.0.1 localhost ...` / `::1 localhost`) and [`_writeNsswitchConf`](lib/core/services/runtime_service.dart) (`hosts: files dns`), bind-mounted them in `init-host` and Android [`ProcessManager`](android/app/src/main/kotlin/com/example/quantum_ide/ProcessManager.kt), and generated them in [`BootstrapManager.writeResolvConf`](android/app/src/main/kotlin/com/example/quantum_ide/BootstrapManager.kt).
- **Editor Accessory Bar Theme Consistency (`KeyboardAccessoryBar`)**:
  - Replaced hardcoded black/slate backgrounds (`#0D0F14`, `#131722`, `#141720`, `#161927`) in [`KeyboardAccessoryBar`](lib/features/editor/presentation/widgets/keyboard_accessory_bar.dart) (toolbar with Undo/Redo/Arrows/Copy/Search, symbol keys, line/col pill, snippet sheet, and go-to-line dialog) with active `ConduitPalette` (`resolveConduitPalette`) and `Theme.of(context).colorScheme` colors.

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
