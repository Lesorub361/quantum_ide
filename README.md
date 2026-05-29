# 🚀 QuantumIDE

QuantumIDE is a next-generation, AI-powered mobile Integrated Development Environment (IDE) built specifically for web development, running natively on Android using Flutter. It provides a complete development environment including a code editor, local terminal sandbox, Git, and advanced AI assistance.

---

## 🛠️ Technology Stack

- **Framework**: [Flutter](https://flutter.dev) (Material 3, customized layout)
- **State Management**: [Riverpod](https://riverpod.dev)
- **Navigation**: [GoRouter](https://pub.dev/packages/go_router)
- **Code Editor**: `re_editor` + `re_highlight`
- **Terminal & Shell**: `xterm.dart` + `flutter_pty`
- **AI Engine**: `google_generative_ai` (Gemini) + custom connectors for DeepSeek, Groq, OpenRouter, and Local AI (Ollama/LM Studio)
- **Design & Themes**: `flex_color_scheme` + glassmorphic visual effects
- **Typography**: *Outfit* (for UI) & *JetBrains Mono* (for Code)

---

## 📂 Project Structure

Below is the directory structure of the application source code (`lib/`):

*   **`lib/main.dart`**: Application entrypoint.
*   **`lib/app.dart`**: Main configuration of `MaterialApp`, themes, and router.
*   **`lib/core/`**: Core services and system-wide state:
    *   `models/`: Core models like code diagnostics and AI configurations.
    *   `providers/`: App-level providers (e.g. localization).
    *   `router/`: Navigation and routing rules via GoRouter.
    *   `theme/`: Dynamic theme configuration (FlexColorScheme, glassmorphism styles).
    *   `utils/`: Conversion utilities, path mappings (host <-> sandbox).
    *   `services/`: Background processing and platform services:
        *   `ai_service.dart`, `ai_autocomplete_service.dart`, `ai_context_compressor.dart`: AI integration.
        *   `lsp_service.dart`, `lsp_autocomplete_service.dart`, `analysis_service.dart`: Code intelligence, diagnostics, and LSP.
        *   `git_service.dart`, `diff_service.dart`: Git operations and gutter diff markers.
        *   `runtime_service.dart`, `native_terminal.dart`: Android PRoot setup and shell process bridge.
        *   `package_service.dart`, `pub_package_service.dart`: APT packages, Android build toolchain, and pub.dev API.
        *   `workspace_service.dart`, `project_service.dart`: Workspaces, build orchestrator, and templates.
        *   *New services in progress*: `ai_agent_orchestrator.dart`, `crdt_sync_service.dart`, `microvm_service.dart`, `wasm_plugin_runner.dart`.
*   **`lib/features/`**: Feature-driven modules:
    *   `ai_assistant/`: Real-time AI chat panel, settings, and MCP (Model Context Protocol) configs.
    *   `editor/`: Code editor, tabs manager, autocomplete, code diagnostics panel, outline, and accessory bar.
    *   `file_explorer/`: Bookmarks, tree view, search panel, and disk analyzer widget.
    *   `git/`: Version control panel, diff viewer, and merge conflicts solver page.
    *   `home/`: Home/launch screen, project templates, local servers launcher, and IDE settings.
    *   `preview/`: Browser preview, console logging, and debugging controls.
    *   `terminal/`: Multi-tab terminal interface, virtual keys panel, and Gradle/APK signing widgets.
    *   *New modules in progress*: `collaboration/` (Live Share), `plugins/` (WASM plugin manager).
*   **`lib/models/`**: Shared data models (e.g., chat sessions, package models).
*   **`lib/shared/`**: Global widgets:
    *   `layout/`: Dynamic screen split manager (`foldable_split_manager.dart`).
    *   `widgets/`: Glass containers, breadcrumbs, status bars, and layout scaffolding.
*   **`lib/l10n/`**: Localization resources (RU/EN/ES/FR).

---

## 🟢 Implemented Features

- **Workspace Management**: Android Storage Access Framework (SAF) folder picker, project templates, bookmarks, recent workspaces.
- **Quantum Editor**: Virtualized text rendering, real-time syntax highlighting for multiple languages, autosave, tabs, visual diff indicators, diagnostics, customizable keyboard accessory keys.
- **Embedded Sandbox Terminal**: Native terminal PTY integration running an Ubuntu 24.04 PRoot environment. Automounts android storages, supports auto-recovery, customized `.bashrc`, dynamic tools configuration.
- **Language Server Protocol (LSP)**: Complete support for HTML, CSS, JavaScript, and TypeScript within the PRoot sandbox. Offers smart autocomplete, documentation hovers, usages lookup, rename refactoring, and code formatting.
- **Live Share (Real-time Collaboration)**: Host or join shared coding sessions over local networks. Synchronizes document text changes instantly using diff-match-patch alongside remote cursor caret lines, selections, and floating developer name flags. Includes a built-in session developer chat.
- **Multi-backend AI Assistant**: Built-in chat panel supporting Google Gemini (Flash & Pro), Groq, DeepSeek, OpenRouter, and local models (Ollama/LM Studio). Smart debounced (700ms) code autocompletion.
- **Built-in Git Client**: Diff tool, status tracker, visual conflict solver, and commit flow integration.
- **Mobile Build Tools & Diagnostics**: Automated ARM64 Linux toolchain setup (NDK, SDK symlinking, AAPT2 patcher), Java JDK 17 setup, background `dart analyze` processing, project-wide problems panel, APK building and signing.
- **Web Preview**: Built-in chromium-based WebView previewing, console log forwarder, local server listener.
- **Premium Design System**: Glassmorphism (blur filters), smooth micro-animations, customizable project accent colors, Outfit and JetBrains Mono typography, custom Lucide icons.
- **Localization**: Multi-language support including English, Russian, Spanish, and French, with an in-app language selection dialog.

---

## 🔮 Roadmap / Future Tasks

Here are the features currently in development or planned:

- [x] **LSP Integration**: Add language server support for HTML, CSS, JavaScript, and TypeScript inside the sandbox for full auto-complete, go-to-definition, and complex linting. (Completed)
- [x] **Live Collaboration (Live Share)**: Add real-time multiplayer editing using CRDT/diff-match-patch synchronization with cursor sharing and voice/chat options. (Completed)
- [x] **WASM Plugin System**: Add support for running WebAssembly-based custom plugins compiled from Rust, Go, or C++ to extend the editor's capabilities. (Completed)
- [ ] **KVM MicroVM Integration**: Support hardware-accelerated Linux kernels inside lightweight micro-VMs on Android 15+ to bypass PRoot constraints.
- [ ] **Foldable Layout Support**: Auto-splitting panels (terminal/editor/preview) across physical screen folds on foldable smartphones and tablets.
- [ ] **Local AI completions (MLC LLM)**: Integrate Qwen-Coder or Llama-3-Coder running directly on the device's NPU.
- [ ] **Docker & Container Support**: Enable lightweight containers inside the development sandbox.
- [ ] **Remote SSH Development**: Connect to and edit files on remote servers directly from the IDE.
- [ ] **Themes & Plugins Marketplace**: Discover and install community-developed themes and extension plugins.

---

## 🤝 Join the Development! (We welcome contributors)

We are actively looking for developers, designers, and open-source enthusiasts to join our project! Whether you want to fix bugs, write documentation, implement features from the roadmap, or test the IDE on different devices, you are very welcome.

### How to Contribute:
1. **Fork** the repository and clone it locally.
2. Check out the roadmap above or browse open GitHub Issues.
3. Set up the development environment:
   ```bash
   flutter pub get
   flutter run
   ```
4. Create a feature branch, commit your changes, and submit a **Pull Request**.

If you have questions or want to discuss architecture, feel free to join our chat/discussions or open an issue!

---

## 📜 License

This project is licensed under the MIT License - see the `LICENSE` file for details.
