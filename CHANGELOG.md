# Changelog

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
