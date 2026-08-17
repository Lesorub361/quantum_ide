# Changelog

## 1.2.2
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
