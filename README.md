<div align="center">

# ⚡ QuantumIDE

**Next-Gen AI-Powered Mobile & Desktop Studio built with Flutter**

[![Build APK](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-apk.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-apk.yml)
[![Build Linux](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-linux.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-linux.yml)
[![Build Windows](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-windows.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-windows.yml)
[![Build macOS](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-macos.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-macos.yml)
[![Build iOS](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-ios.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-ios.yml)
[![Build Web](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-web.yml/badge.svg)](https://github.com/Lesorub361/quantum_ide/actions/workflows/build-web.yml)

**Основная ветка разработки:** `flutter-3.50` · **Релизы:** [`v1.2.217`](https://github.com/Lesorub361/quantum_ide/releases/latest)

</div>

---

## 📱 Поддерживаемые устройства и платформы

QuantumIDE собирается автоматически через GitHub Actions для всех основных мобильных, десктопных и веб-платформ:

| Платформа | Архитектура / Формат | Статус | Примечание |
| :--- | :--- | :---: | :--- |
| **Android** | `arm64-v8a`, `armeabi-v7a`, `x86_64` (`.apk` / `.aab`) | ✅ Полная поддержка | Встроенный Ubuntu 24.04 PRoot, сборка Flutter/APK прямо на телефоне |
| **Linux Desktop** | `x64`, `arm64` (`.tar.gz`) | ✅ Поддерживается | Нативный терминал + системный toolchain |
| **Windows Desktop** | `x64` (`.zip`) | ✅ Поддерживается | Десктопный редактор, AI-агент и Git |
| **macOS** | Universal / Apple Silicon (`.zip`) | ✅ Поддерживается | Десктопный редактор, AI-агент и Git |
| **iOS** | Unsigned `.ipa` | 🧪 Экспериментально | Доступна сборка без подписи через CI |
| **Web** | PWA / Static Web Bundle | ✅ Поддерживается | Веб-версия редактора и AI-ассистента |

> 📥 **Скачать готовые сборки для всех устройств:** [GitHub Releases](https://github.com/Lesorub361/quantum_ide/releases/latest)

---

## ✨ Что уже реализовано в проекте

### 🤖 AI-агент и умное автодополнение (Roxum Agent + CodeCrafter)
- **Roxum AI Agent & Chat UI**: полноценный чат-ассистент в режимах **Ask** и **Agent** с историей сессий, переключателем моделей и настройкой прав для каждого инструмента.
- **20 агентских инструментов**: чтение/поиск/правка файлов, диагностика ошибок, Git (`status`, `diff`, `log`), выполнение команд в Ubuntu PRoot, а также **Keep / Undo Diff** — просмотр и подтверждение или откат каждого изменения, сделанного агентом.
- **CodeCrafter Inline AI**: встроенное дебаунс-автодополнение кода на базе [`flutter_code_crafter`](packages/flutter_code_crafter) прямо в редакторе.
- **Мультипровайдерность**: Google Gemini, DeepSeek, OpenAI, Anthropic Claude, OpenRouter, Groq, xAI Grok, Mistral, а также локальные модели (Ollama / `llama.cpp` / Custom OpenAI-compatible API).

### 💻 Терминал нового поколения (Conduit Terminal Engine)
- **Движок [`conduit_vt`](packages/conduit_vt)**: быстрый рендеринг VT-последовательностей, точное выделение текста и **встроенная экранная лупа (magnifier)** при выделении текста на мобильных экранах.
- **16 цветовых палитр и кастомизация**: гибкая настройка фона, прозрачности, шрифта `AtkynsonMonoNerdFontMono` и раскладки виртуальной клавиатуры (`ConduitKeyboardBar`).
- **Ubuntu 24.04 PRoot Sandbox**: полноценная Linux-среда на Android с автоматическим предложением обновления rootfs и красивым Neofetch-приветствием (`term-fetch`).

### 📝 Редактор, LSP и быстрое хранилище
- **Быстрая работа с проектами**: проекты хранятся напрямую во внутреннем окружении `/root/projects` без фоновой синхронизации с медленным `/storage/emulated/0/QuantumIDE` — мгновенный отклик редактора без задержек FUSE. Импорт и экспорт проектов доступны вручную через интерфейс или проводник.
- **Quantum Editor**: подсветка синтаксиса (`re_editor` + `re_highlight`), мультикурсор, minimap, diff-маркеры на полях, горячие клавиши и панель проблем (`ProblemsPanel` на базе `dart analyze` + LSP).
- **LSP (Language Server Protocol)**: автодополнение, переходы к определениям и диагностика для Dart, HTML, CSS, JavaScript и TypeScript.
- **Системный очиститель (System Cleaner)**: очистка временных кешей, логов, `pub`/Gradle-артефактов и освобождение памяти прямо из интерфейса IDE.
- **Git, Live Share и WebView Preview**: визуальный diff и решение конфликтов слияния, совместное редактирование в реальном времени и встроенный предпросмотр веб-приложений.

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
- [x] **Roxum AI Agent & CodeCrafter**: интеграция агентского чата с diff-ревью и inline-автодополнением кода.
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
