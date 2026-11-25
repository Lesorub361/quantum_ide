<div align="center">

# ⚡ QuantumIDE

**Next-Gen AI-Powered Mobile & Desktop Studio built with Flutter**

[![Build APK](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-apk.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-apk.yml)
[![Build Linux](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-linux.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-linux.yml)
[![Build Windows](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-windows.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-windows.yml)
[![Build macOS](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-macos.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-macos.yml)
[![Build iOS](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-ios.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-ios.yml)
[![Build Web](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-web.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-web.yml)

**Основная ветка разработки:** `main` · **Актуальный релиз:** [`v1.2.308`](https://github.com/Lesorub361/quantum_ide/releases/latest)

</div>

---

## 📱 Поддерживаемые устройства и платформы

QuantumIDE собирается автоматически через GitHub Actions для всех основных мобильных, десктопных и веб-платформ:

| Платформа | Архитектура / Формат | Статус | Примечание |
| :--- | :--- | :---: | :--- |
| **Android** | `arm64-v8a`, `armeabi-v7a`, `x86_64`, Universal (`.apk` / `.aab`) | ✅ Полная поддержка | Встроенный Ubuntu 24.04 PRoot **или** работа напрямую на ядре устройства с Root-правами (`su`) без скачивания Ubuntu |
| **Linux Desktop** | `x64`, `arm64` (`.tar.gz`) | ✅ Поддерживается | Открытие проектов на месте (in-place), автопоиск `flutter`/`agy`/SDK + нативный терминал |
| **Windows Desktop** | `x64`, `arm64` (`.zip`) | ✅ Поддерживается | Открытие проектов на месте, выбор папки проекта, автопоиск SDK, AI-агент и Git |
| **macOS** | Universal / Apple Silicon (`.zip`) | ✅ Поддерживается | Нативная работа с проектами, автопоиск Homebrew/Flutter SDK, AI-агент и Git |
| **iOS** | Unsigned `.ipa` | 🧪 Экспериментально | Доступна сборка без подписи через CI |
| **Web** | PWA / Static Web Bundle (`.tar.gz` / `.zip`) | ✅ Поддерживается | Веб-версия редактора и AI-ассистента |

> 📥 **Скачать готовые сборки для всех устройств:** [GitHub Releases](https://github.com/Lesorub361/quantum_ide/releases/latest)

---

## ✨ Что уже реализовано в проекте

### 🤖 AI-агент профессионального уровня (ACP: OpenCode / Gemini CLI / Claude Code + Roxum Built-in + MCP)
- **Нативная интеграция внешних кодинг-агентов по стандарту Agent Client Protocol (`acp_dart ^0.5.0`)**: подключает напрямую **OpenCode (`opencode acp`)**, **Gemini CLI (`gemini --experimental-acp`)** и **Claude Code (`claude-code-acp`)** прямо в чат QuantumIDE с автопробросом API-ключей, живым стримингом мыслей/инструментов/diff-ов, автообновлением редактора и установкой CLI в 1 клик.
- **Авто-диагностика `errorsOnly` внутри `writeFile` / `editFile` / `multiEditFile`**: во встроенном движке Roxum Built-in правки автоматически проверяются через `dart analyze` без шума `info`/`warning` при `0 error(s)`, с защитой от неоднозначных замен, таймаутом 45с на зависание SSE-потока и сжатием больших `readFile` (-75% токенов).
- **Пакетная правка `multiEditFile` и нечёткий поиск блоков**: исправление сразу нескольких ошибок в одном файле за 1 вызов с устойчивостью к сдвигам отступов и защитой от потери существующего кода (`// ... existing code`).
- **Живой Verification Gate, Loop Guard и умное сжатие контекста**: защита от обрыва ответа на полуслове, блокировка зацикленных вызовов и сохранение актуальной диагностики при сжатии истории.
- **Визуальный таймлайн действий в стиле Antigravity**: живая карточка хода работы агента с цветными иконками языков (`Dart`, `JS/TS`, `Python`, `HTML`, `JSON`, `Bash`), статистикой изменений (`+N -M`), индикатором `Running...` и переходом к файлу в редакторе.
- **7 встроенных нативных MCP-серверов с контекстной подгрузкой (0 токенов на простой, без Node/Python)**:
  - `quantum-codegraph` — индекс символов проекта, чтение конкретных классов/методов (`read_symbol`), поиск использований и BM25-поиск.
  - `quantum-token-saver` — компактная диагностика ошибок без дублей, запуск тестов и сканирование `TODO`/`FIXME`.
  - `quantum-build-doctor` & `quantum-device-qa` — диагностика сборок Gradle/NDK, подбор флагов под RAM/CPU, ADB/Logcat и статус Shizuku.
  - `quantum-sqlite-telemetry`, `quantum-web-fetch`, `quantum-memory` — инспекция SQLite/сети, поиск документации и долговременная память проекта.
- **CodeCrafter Editor & LSP Bridge (`flutter_code_crafter`)**: редактор кода с подсветкой синтаксиса для всех языков (`allLanguages`), фолдингом, брейкпоинтами, направляющими отступов, AI inline-дополнением и мостом к `LspService`.
- **Мультипровайдерность и умное ранжирование моделей**: Google Gemini, DeepSeek, OpenAI, Anthropic Claude, OpenRouter (с автоприоритетом `Qwen Coder`, `DeepSeek V3`, `Claude`, `Gemini`, `Llama 3.3 70B`), Groq, xAI Grok, Mistral и локальные серверы (Ollama / `llama.cpp`).

### 💻 Терминал нового поколения (Conduit Engine) и Root-режим без скачивания Ubuntu
- **Движок [`conduit_vt`](packages/conduit_vt)**: быстрый рендеринг VT-последовательностей, кликабельные ссылки (`Ctrl+клик` / одиночный тап по URL), автокопирование при выделении и **экранная лупа (magnifier)** на мобильных экранах.
- **Режим Native Root Kernel (`su` без скачивания Ubuntu)**: если на Android-устройстве есть Root-права (**Magisk / KernelSU / APatch**), пользователь может включить работу **напрямую на своём ядре Linux/Android** без скачивания архива Ubuntu 24.04 и без прослойки PRoot — с максимальной скоростью ввода-вывода и прямым доступом к оборудованию.
- **Ubuntu 24.04 PRoot Sandbox (для устройств без Root)**: полноценная Linux-среда на Android с GLIBC 2.39, автообновлением rootfs, сверхбыстрыми пакетными менеджерами **`uv`** (Python), **`bun`** (ARM64 JS/TS) и **`pnpm`**, а также приветствием `term-fetch`.
- **Нативная работа с путями на всех ОС (Android, Linux, Windows, macOS)**:
  - На **ПК (Linux / Windows / macOS)** проекты при импорте открываются **мгновенно в своей родной папке** (in-place, без копирования в `.quantum_ide/projects`), а при создании нового проекта доступна видимая папка `~/QuantumIDEProjects` и выбор любой директории через **«Обзор...»**.
  - На карточках проектов отображается полный путь на диске и кнопка **«Показать в файловом менеджере»**.
  - На **Android** проекты работают в быстром внутреннем хранилище `/root/projects` с прозрачной трансляцией путей между хостом и контейнером.

### 📝 Редактор, Профессиональный Git и Инструменты
- **Профессиональный Git-клиент**: визуальный граф коммитов (`CustomPainter`), управление локальными и удалёнными ветками (создание, переключение, слияние, удаление), Stash, история коммитов с просмотром изменённых файлов и синхронизация с пользовательским фоном IDE.
- **Quantum Editor & LSP**: автодополнение, переходы к определениям и диагностика для Dart, HTML, CSS, JavaScript, TypeScript и Python.
- **Системный очиститель (System Cleaner)**: очистка временных кешей, логов, `pub`/Gradle-артефактов и освобождение памяти прямо из интерфейса IDE.

### ⚡ Сборка APK / AAB на Android (Flutter, Java, Kotlin)
- ✅ **Защита от вылетов (OOM / Android LMK)**: автоматический подбор безопасных лимитов памяти (`jvmHeap`, `dartHeap`, `workers`, `CMAKE_BUILD_PARALLEL_LEVEL`, `kotlin.daemon.jvm.options=-Xmx512m`) под свободную RAM устройства (`MemAvailable`).
- ✅ **Поддержка Java и Kotlin проектов из коробки**: единая обёртка `gradlew` с нативным ARM64 `/usr/bin/aapt2`, `--console=plain`, `org.gradle.vfs.watch=false`, `in-process` компиляцией Kotlin и `Build Doctor`.
- ✅ **Ускоренная сборка без лишних тормозов**: точечное применение флагов `Box64` только для `gen_snapshot` (без замедления OpenJDK, Gradle, R8 и C++), кэш-проверка окружения и авто-подхват нативного ARM64 `gen_snapshot` при наличии в релизах.
- ✅ **Плавный UI во время сборки**: кэшированный разбор логов и диагностик в `BeautifulLogsViewer` и батчирование прогресса сборки без фризов интерфейса.

---

## 🛠️ Технологический стек

- **Framework**: Flutter 3.47+ / Dart 3.11+ (Material 3, `flex_color_scheme`, `flutter_lucide`)
- **State Management**: `flutter_riverpod`
- **Routing**: `go_router`
- **Code Editor & AI Completion**: `re_editor`, `re_highlight`, `flutter_code_crafter`
- **Terminal & PTY**: `conduit_vt`, `flutter_pty`, Ubuntu 24.04 PRoot
- **AI & Markdown**: `roxum` Agentic Engine (`http`), `gpt_markdown`
- **Diagnostics & Logging**: `talker_flutter`, `dart analyze`
- **Localization**: `flutter_localizations` (RU / EN / ES / FR / ZH)

---

## 📂 Актуальная структура проекта

```text
quantum_ide/
├── lib/
│   ├── main.dart                     # Точка входа приложения
│   ├── app.dart                      # Конфигурация MaterialApp, тем и GoRouter
│   ├── core/
│   │   ├── models/                   # Модели диагностики и AI-конфигураций
│   │   ├── providers/                # Глобальные провайдеры (тема, локаль)
│   │   ├── router/                   # Маршрутизация GoRouter
│   │   ├── services/                 # Runtime/PRoot, LSP, Git, CodeCrafter AI, Talker, Settings
│   │   ├── theme/                    # FlexColorScheme, палитры, glassmorphism
│   │   └── utils/                    # Конвертация путей (host <-> PRoot)
│   ├── features/
│   │   ├── ai_assistant/             # Roxum AI Agent (roxum/), чат-панель и MCP
│   │   ├── collaboration/            # Live Share (совместная работа)
│   │   ├── editor/                   # Редактор кода, вкладки, ProblemsPanel, диффы
│   │   ├── file_explorer/            # Дерево проекта, поиск, закладки
│   │   ├── git/ & github/            # Git-клиент, граф коммитов, интеграция с GitHub
│   │   ├── home/                     # Дашборд, шаблоны, менеджер пакетов, System Cleaner
│   │   ├── plugins/                  # Система расширений
│   │   ├── preview/                  # Встроенный WebView-просмотр и консоль
│   │   ├── rest_client/              # Встроенный HTTP/REST-клиент
│   │   └── terminal/                 # Conduit-терминал, палитры, виртуальная клавиатура
│   ├── l10n/                         # Файлы локализации (RU/EN/ES/FR/ZH)
│   └── shared/                       # Общие виджеты и адаптивный split-screen
└── packages/
    ├── conduit_vt/                   # Vendored терминальный VT-движок + лупа выделения
    └── flutter_code_crafter/         # Vendored пакет AI-автодополнения и LSP-утилит
```

---

## 🔮 Планы на будущее (Roadmap)

- [x] **Conduit Terminal & Selection Loupe**: полная замена движка терминала, 16 тем оформления и экранная лупа выделения.
- [x] **Roxum AI Agent & CodeCrafter**: интеграция агентского чата с diff-ревью, визуальным таймлайном шагов в стиле Antigravity и inline-автодополнением кода.
- [x] **Native Root Kernel Mode (`su`)**: работа напрямую на ядре Android-устройства с Root-правами без скачивания Ubuntu 24.04 PRoot.
- [x] **4 встроенных нативных MCP-сервера & автопоиск SDK**: `quantum-code-intel`, `quantum-git-ops`, `quantum-pkg-manager`, `quantum-memory`, автообнаружение `flutter`/`agy`/SDK и работа с проектами на ПК по их реальным путям.
- [x] **System Cleaner & Auto Rootfs Upgrade**: встроенная очистка системы и автообновление Ubuntu 24.04 PRoot.
- [ ] **KVM MicroVM (Android 15+)**: аппаратная виртуализация Linux-ядра без ограничений PRoot.
- [ ] **Адаптация под складные экраны (Foldables)**: автоматическое разделение редактора, терминала и превью по линии сгиба.
- [ ] **Контейнеры и Docker**: запуск изолированных сервисов и баз данных внутри рабочего окружения.
- [ ] **Remote SSH**: полноценная разработка на удалённых серверах прямо из QuantumIDE.
- [ ] **Маркетплейс тем и плагинов**: установка пользовательских тем оформления и расширений в 1 клик.

---

## 🤝 Благодарности и лицензии

В проекте используются и адаптированы компоненты с открытым исходным кодом (MIT License):
- [Conduit](https://github.com/gwitko/Conduit) — терминальный движок `conduit_vt`
- [flutter_code_crafter](https://github.com/heckmon/flutter_code_crafter) — AI-автодополнение кода и LSP-утилиты
- [roxum-ide](https://github.com/heckmon/roxum-ide) — логика AI-агента, каталог инструментов и UI чата
