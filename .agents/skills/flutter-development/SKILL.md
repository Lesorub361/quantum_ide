---
name: flutter-development
description: >-
  Use this skill when developing, refactoring, analyzing, or fixing Flutter and Dart code in this project.
---

# Flutter & Dart Quality Guide for QuantumIDE

This skill provides step-by-step procedures to write, analyze, and format code in QuantumIDE.

## 1. Code Analysis

After making any code modifications, verify the code using `dart analyze`:

```bash
# Analyze a single file
dart analyze lib/path/to/file.dart

# Or analyze the entire lib directory (or specific feature)
dart analyze lib/features/editor/
```

### Addressing Common Linter Warnings
- **`use_build_context_synchronously`**: Add `if (!context.mounted) return;` immediately before accessing `context` or `Navigator` after an `await`.
- **`cancel_subscriptions`**: Always cancel `StreamSubscription` instances in the `dispose()` method.
- **`prefer_const_constructors`**: Add `const` before immutable widget constructors.
- **`prefer_final_locals`**: Declare local variables that are never reassigned with `final`.
- **`prefer_single_quotes`**: Use single quotes `'...'` for strings, unless double quotes are needed to avoid escaping single quotes.
- **`avoid_print`**: Replace `print(...)` with `ref.read(talkerServiceProvider).info(...)` or appropriate logging methods.

## 2. Formatting

Ensure code formatting matches the project standard:

```bash
dart format lib/path/to/file.dart
```

## 3. Riverpod State Guidelines

- In widgets, use `ConsumerWidget` or `ConsumerStatefulWidget`.
- Inside `build(BuildContext context, WidgetRef ref)`:
  - Use `ref.watch(provider)` to listen to values.
  - Avoid calling methods that cause side-effects inside `build()`.
- Inside buttons, event handlers, and callbacks:
  - Use `ref.read(provider.notifier).method()`.
