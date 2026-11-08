# Quantum IDE - Project Architecture & Agent Instructions

This document defines the core architecture, conventions, and engineering rules for the **QuantumIDE** project. All code modifications must strictly adhere to these guidelines.

---

## 1. Project Overview & Tech Stack

QuantumIDE is an AI-powered mobile and desktop IDE for web and mobile development, built using Flutter.

- **SDK**: Flutter 3.47+ / Dart 3.13+ (`sdk: ^3.11.4` in `pubspec.yaml`)
- **State Management**: [Riverpod](https://pub.dev/packages/flutter_riverpod) (`flutter_riverpod: ^2.6.1`)
- **Routing**: [GoRouter](https://pub.dev/packages/go_router) (`go_router: ^14.8.1`)
- **Code Editor**: `re_editor` + `re_highlight`
- **Terminal & Shell**: `xterm` + `flutter_pty` + Ubuntu 24.04 PRoot sandbox
- **Design System**: Material 3, `flex_color_scheme`, Lucide icons (`flutter_lucide`), Outfit & JetBrains Mono fonts
- **Logging**: [Talker](https://pub.dev/packages/talker_flutter) (`TalkerService`)
- **Localization**: Flutter l10n with ARB files (`lib/l10n/`)

---

## 2. Directory Layout & Modular Structure

```
lib/
├── main.dart                      # App entry point
├── app.dart                       # MaterialApp, theme configuration, router attachment
├── core/
│   ├── models/                    # Global core data models (diagnostics, AI configs)
│   ├── providers/                 # Top-level providers (e.g. locale, theme)
│   ├── router/                    # GoRouter configuration (app_router.dart)
│   ├── services/                  # Platform, runtime, and background services:
│   │   ├── runtime_service.dart   # PRoot Linux sandbox lifecycle & process spawning
│   │   ├── lsp_service.dart       # Language Server Protocol integration
│   │   ├── git_service.dart       # Local git operations
│   │   ├── mcp_service.dart       # Model Context Protocol client & server integrations
│   │   ├── quantum_ai_agent_service.dart # Multi-turn AI agent engine
│   │   ├── service_providers.dart # Global Riverpod providers for services
│   │   └── talker_service.dart    # Centralized logging service
│   ├── theme/                     # Glassmorphic and FlexColorScheme theming
│   └── utils/                     # Path converters (host <-> PRoot sandbox), helpers
├── features/                      # Feature modules (UI, state, widgets per feature):
│   ├── ai_assistant/              # AI chat, MCP tools dialogs, completions
│   ├── editor/                    # Code editor tabs, diagnostics, accessory bar
│   ├── file_explorer/             # Project tree, bookmarks, search
│   ├── git/                       # Git status, commits, visual diffs
│   ├── home/                      # Project dashboard, settings, local servers
│   ├── preview/                   # In-app WebView preview & console
│   └── terminal/                  # PTY terminal tabs, virtual keyboard
├── models/                        # Cross-feature data models
└── shared/                        # Reusable UI widgets and split-view layouts
```

---

## 3. Strict Coding Conventions & Lint Rules

All code must comply with `analysis_options.yaml`:

1. **Async Safety**:
   - Always check `if (!mounted) return;` (in `StatefulWidget`) or `if (!context.mounted) return;` (when using `BuildContext`) across any `await` boundary.
   - Never use `BuildContext` in an async callback without checking `mounted`.

2. **State Management with Riverpod**:
   - Prefer `NotifierProvider` / `AsyncNotifierProvider` or `StateNotifierProvider` for stateful logic.
   - Use `ref.watch()` only inside `build()` methods to subscribe to changes.
   - Use `ref.read()` inside callbacks, event handlers, and lifecycle hooks (`initState`, `dispose`).
   - Always register cleanup in `ref.onDispose(() => service.dispose())`.

3. **Logging & Diagnostics**:
   - **Never use `print()`**. Use `TalkerService` or `talker.info(...)` / `talker.error(...)` / `talker.warning(...)`.
   - All critical background errors must be routed to `talker` so users can inspect them in the DevTools / Logs view.

4. **Formatting & Style**:
   - Prefer `const` constructors wherever possible (`prefer_const_constructors`).
   - Prefer `final` local variable declarations (`prefer_final_locals`).
   - Prefer single quotes for strings (`prefer_single_quotes`).
   - Avoid empty or unnecessary `Container()` widgets.
   - Ensure null safety: avoid force-unwrapping `!` unless nullability is proven via previous checks.

5. **Sandbox & File Paths**:
   - Remember that paths inside the PRoot terminal sandbox (`/home/...`) differ from Android/host paths.
   - Use path translation helpers in `lib/core/utils/` when translating paths between the host app and PRoot.

---

## 4. Verification Workflow

Before completing any task or code edit:
1. Run `dart analyze <path_to_file>` or `flutter analyze` via terminal to verify zero compilation errors or fatal warnings.
2. Format updated Dart files using `dart format <path_to_file>` if needed.
3. Keep changes minimal, clean, and directly related to the user request.
