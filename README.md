# QuantumIDE

QuantumIDE is a next-generation, AI-powered mobile IDE for web development that runs natively on Android and is built with Flutter. It provides a full developer environment — code editor, terminal, isolated sandbox, Git integration, and an intelligent assistant — so you can build, run, and ship apps right from your phone.

---

## Tech Stack

- **Framework:** [Flutter](https://flutter.dev) (Material 3, adaptive layout)
- **State management:** [Riverpod](https://riverpod.dev)
- **Routing:** [GoRouter](https://pub.dev/packages/go_router)
- **Editor core:** `re_editor` + `re_highlight`
- **Terminal emulator:** `xterm.dart` + `flutter_pty`
- **AI core:** `google_generative_ai` (Gemini) + custom connectors for DeepSeek, Groq, OpenRouter, and local AI (Ollama / LM Studio / Mistral.rs / MLC LLM)
- **Theming:** `flex_color_scheme` + glassmorphism effects
- **Typography:** *Outfit* (UI) and *JetBrains Mono* (code)

---

## Features

- **Workspace manager:** pick folders via Android Storage Access Framework (SAF), bookmarks, project templates, recent files.
- **Quantum Editor:** line virtualization, syntax highlighting for many languages, autosave, tabs, change indicator, linter, and a custom quick-symbol bar.
- **Built-in terminal & sandbox:** a PTY terminal backed by an Ubuntu 24.04 PRoot environment. Auto-mounts Android storage, supports autostart, process auto-recovery, and a custom `.bashrc`.
- **LSP support:** full language-server integration for HTML, CSS, JavaScript, and TypeScript — autocomplete, docs hover, find references, rename, and format.
- **Live collaboration (Live Share):** create/join real-time sessions over the local network. CRDT-synced edits, named remote cursors/selections, and an in-session chat.
- **AI Assistant (multi-model):** in-app chat with Google Gemini, Groq, DeepSeek, OpenRouter, and local models (Ollama / LM Studio / Mistral.rs). Streaming responses, visible reasoning, and a clean Chat mode that can read files and search the web to answer.
- **AI Agents:** autonomous actions — create files, run commands, fix errors — driven by JSON scenarios with rollback support.
- **Git integration:** view changed files, commit, a side-by-side visual diff viewer, and a graphical merge-conflict resolver.
- **MicroVM (KVM):** hardware virtualization of Linux on Android 15+ (fallback to PRoot on older devices).
- **Docker / Podman:** run and orchestrate containers inside the sandbox with Android storage mounted.
- **SSH development:** connect to remote servers, run commands, transfer files, manage connections.
- **Local autocomplete (MLC LLM):** lightweight on-device models via the device NPU — no internet required.
- **In-app APK build & release:** commit changes and trigger a GitHub Actions build that produces a downloadable, signed release APK.

---

## Building

See [BUILD_GUIDE.md](BUILD_GUIDE.md) and [BUILD_ANDROID_ARM64.md](BUILD_ANDROID_ARM64.md) for local build instructions. The easiest path is the in-app build flow, which commits your changes and triggers a GitHub Actions release build.

---

## Changelog

### 1.1.6

**Git-панель теперь связана с вашим GitHub**
- Push и Pull в боковой Git-панели автоматически авторизуются через сохранённый GitHub-токен (вставляется в экране GitHub). Можно коммитить и отправлять изменения прямо из редактора.

**In-app «Сборка и публикация»**
- Новый экран (кнопка 🚀 в GitHub): вставляете токен, указываете версию и заметки к релизу, нажимаете «Собрать и опубликовать».
- Приложение само коммитит новую версию в `pubspec.yaml`, запускает GitHub Actions и показывает прогресс сборки и ссылку на готовый релиз.
- Workflow принимает входные параметры `version` и `release_notes`, поэтому описание релиза формируется из того, что вы написали.

### 1.1.5

**Local AI engines**
- Added **Mistral.rs (Rust)** as a local engine — a fast Rust LLM server, noticeably quicker than llama.cpp on CPU. Point it at a `mistralrs-server` over the network (OpenAI-compatible API).
- **LM Studio** remains available as a local engine.
- Local engine model lists no longer show fake default models — only real ones: downloaded catalog models for the built-in engine, or models actually loaded in Ollama / LM Studio / Mistral.rs.

**Model storage**
- On mobile, downloaded models are now saved next to your projects (`<app>/projects/ai_models`), so they survive and can be re-added or swapped manually from the file manager.

**Chat experience**
- Chat mode is now a clean conversational assistant (à la OpenCode): streamed output, visible reasoning, and it may read files / search the web to answer — but it never loops as an autonomous agent. File-modifying actions are still proposed for confirmation.
- Agent / Autopilot mode stays for autonomous implementation.

**Networking**
- Added a **LAN scanner** in Local AI settings: auto-discovers Ollama (`:11434`), Mistral.rs / LM Studio (`:1234`), llama-server (`:8080`) and other OpenAI-compatible servers on your Wi-Fi, with one-tap connect.
- Added a "Test connection" action for local servers.

---

## License

See repository for details.
