# QuantumIDE — Инструкция по сборке Android на arm64 хостах

## Проблемы, которые решает этот проект

При сборке Flutter-проекта на arm64 машине (например, Raspberry Pi, ARM-сервер, терминал Termux/PRoot) возникают следующие проблемы:

1. **NDK «заглушки»** — в официальных NDK 25/27/28 для Linux-ARM64 файлы `libgcc.a` и `libatomic.a` — пустые заглушки (8 байт). Это ломает линковку нативных плагинов (`jni`, `flutter_pty`, `llama`, `litert`): ошибки `__emutls_get_address`, `operator new`, `_Unwind_Resume`, `std::mutex`.

2. **aapt2 только x86_64** — Google не публикует arm64-версию `aapt2`. Debian-пакет `aapt2` (v2.19) падает на `android-36` (segfault / corrupt ARSC).

3. **Системный clang вместо NDK** — бинарники `clang`/`clang++` в NDK заменены на обёртки к `/usr/bin/clang` (Ubuntu 18.1.3). Он не знает Android-дефолты: не линкует `libc++`, не подключает builtins, не использует полную `libc.so` с `_Unwind_*`.

---

## Быстрое решение (один раз)

```bash
cd /root/projects/quantum_ide
chmod +x setup-android-build.sh
sudo ./setup-android-build.sh
```

Скрипт:
1. Устанавливает `qemu-user-static` (для запуска x86_64 aapt2).
2. Скачивает x86_64 `libc6` + `libgcc-s1` → создаёт sysroot для qemu.
3. Скачивает настоящий Google `aapt2` (x86_64) и упаковывает в обёртку под qemu.
4. Заменяет все `aapt2` в `build-tools/34|35|36` на qemu-обёртку.
5. Патчит **все** установленные NDK (25, 27, 28): заменяет пустые `libgcc.a`/`libatomic.a` на настоящие `libclang_rt.builtins`.
6. Ставит `clang`-обёртку, которая:
   - подключает `-lc++ -lc++abi`
   - использует `libc.so` из api≥30 (там есть `_Unwind_Resume`, `_Unwind_Backtrace`)

---

## Сборка APK

После запуска `setup-android-build.sh`:

```bash
cd /root/projects/quantum_ide
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
```

Результат: `build/app/outputs/flutter-apk/app-release.apk` (~3-5 MB без AI-либ).

---

## Что было убрано из pubspec.yaml (оптимизация размера APK)

| Пакет | Причина удаления | Экономия |
|---|---|---|
| `llama_flutter_android` | ~20 MB `libllama.so` + 20 MB `liblitertlm_jni.so` | ~40 MB |
| `flutter_litert_lm` | Дублирует llama, не используется напрямую | — |
| `xterm` | `flutter_pty` уже даёт PTY-терминал | ~1 MB |
| `diff_match_patch` | Не используется в коде | ~50 KB |
| `desktop_drop`, `contextmenu`, `file_icon`, `watcher` | Desktop-only, тянут web-плагины | ~2 MB |
| 8 шрифтов → 3 (firaCode, jetBrainsMono, sourceCodePro) | Экономия в assets | ~2-3 MB |
| **Итого** | | **~45-47 MB** |

---

## Полезные плагины, которые стоит рассмотреть

| Плагин | Зачем | Статус |
|---|---|---|
| `flutter_quill` | Редактор富文本 (markdown/WYSIWYG) | Альтернатива `flutter_markdown` |
| `dart_code_metrics` | Статический анализ кода в CI | Dev dependency |
| `freezed` + `json_serializable` | Иммутабельные модели, JSON | Уже неявно через riverpod_generator |
| `drift` (бывший moor) | Типобезопасная БД вместо чистого `sqflite` | Если БД сложнее |
| `window_manager` | Управление окном на Desktop | Если собираете Linux/Desktop |
| `universal_io` | `File`/`HttpClient` на Web | Если планируете Web-сборку |

---

## Известные ограничения

- **Только arm64-v8a** — `abiFilters` ограничен одним ABI (экономит память и время сборки). Для x86_64/arm32 нужен другой хост или CI.
- **Минимальный API 26** — `flutter_pty` требует `shm_open` (Android 8+).
- **Подпись** — используется `android/app/release.keystore` (пароль `quantum123`). Для Play Store сгенерируйте свой keystore.
- **Первый запуск скрипта** требует `sudo` и интернета (~50 MB загрузок). Повторные запуски быстрые.

---

## Структура исправлений в коде

```
lib/
├── main.dart          # + PlatformDispatcher.onError, ErrorWidget.builder, runZonedGuarded
├── app.dart           # Fixed customPrimar → customPrimaryColor
android/
├── app/build.gradle.kts  # compileSdk 36, ndkVersion = flutter.ndkVersion, abiFilters arm64-v8a
├── build.gradle.kts      # Clang wrapper применяется к NDK 27/28
├── gradle.properties     # aapt2FromMaven=true, gradle.daemon=false, workers.max=1
scripts/
├── setup-android-build.sh   # Главный скрипт настройки окружения
```

---

## Если что-то сломалось после обновления NDK/SDK/Flutter

1. Перезапустите `sudo ./setup-android-build.sh`
2. `flutter clean && flutter pub get`
3. Снова соберите APK

---

## Автор

Настроено для работы на arm64 хостах (Raspberry Pi 4/5, ARM-серверы, Termux/PRoot, GitHub Actions arm64 runners). Все «заглушки» NDK и проблемы aapt2 решены автоматически.