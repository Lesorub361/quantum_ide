---
name: quantum-architecture
description: >-
  Use this skill when reading, navigating, adding, or modifying services, features, or architectural components in QuantumIDE.
---

# QuantumIDE Architecture Guide

This skill guides the agent in understanding and extending the architecture of the QuantumIDE application.

## 1. Architecture Tiers

### A. Core Platform & Runtime Layer (`lib/core/services/`)
- `runtime_service.dart`: Manages the PRoot Ubuntu sandbox on Android/Linux. Handles mounting internal storage, managing environment variables, starting the rootfs, and running shell commands.
- `native_terminal.dart`: Bridges the PTY process (`flutter_pty`) with the terminal UI (`xterm`).
- `lsp_service.dart`: Communicates via JSON-RPC with language servers (TypeScript, HTML, CSS, Dart) running inside the PRoot sandbox.
- `mcp_service.dart`: Implements Model Context Protocol clients (stdio and SSE/HTTP transports) for connecting custom AI tools.
- `quantum_ai_agent_service.dart`: Autonomous agent engine supporting tool calling, terminal interaction, file editing, and multi-turn planning.
- `service_providers.dart`: Centralized Riverpod providers for global singletons and long-lived services.

### B. Feature Modules (`lib/features/`)
Each feature module contains:
- `data/` or `services/`: Feature-specific data sources and business logic.
- `presentation/`: UI screens (`pages/`) and reusable modular widgets (`widgets/`).
- `providers/`: Riverpod providers managing UI state for the feature.

Key features:
- `features/editor/`: `re_editor` controller integration, tabs bar, visual diff gutters, syntax highlighting engine.
- `features/terminal/`: Terminal tabs, virtual action keys (Ctrl, Alt, Tab, Esc, pipe), session manager.
- `features/ai_assistant/`: Chat UI, MCP server management, code snippet injector.
- `features/file_explorer/`: File tree, directory bookmarks, file operations (create, delete, rename, duplicate).
- `features/git/`: Visual git staging, commits, branches, conflict resolver.

## 2. Standard Service Pattern

When implementing or modifying a service in `lib/core/services/`:
1. Implement a class extending `ChangeNotifier` (or a plain class with `dispose()` method).
2. Clean up streams, processes, and timers in `dispose()`.
3. Expose the service via a provider in `service_providers.dart`:
```dart
final myServiceProvider = Provider<MyService>((ref) {
  final service = MyService();
  ref.onDispose(() => service.dispose());
  return service;
});
```

## 3. Asynchronous Operations & UI Safety
- Never call `setState` or access `context` after an `await` without verifying `mounted`:
```dart
if (!context.mounted) return;
```
- Route exceptions to `talker`:
```dart
ref.read(talkerServiceProvider).error('Failed to start runtime', error, stackTrace);
```
