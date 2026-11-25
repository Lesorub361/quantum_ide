# QuantumIDE — разбор логов с устройства (2026-11-25)

## Устройство / окружение

- Xiaomi Redmi 8 (mi439, olive), 2.9 ГБ ОЗУ
- LineageOS 23.2 (Android 16), ядро `4.19.325-...-dirty`, root через **Magisk 31.1**
- QuantumIDE `v1.2.308` (`com.example.quantum_ide`), режим Ubuntu 24.04 PRoot
- Проект склонирован в `/persistent/home/Lesorub/quantum_ide`

Собранные логи: `/persistent/home/Lesorub/quantum_ide-logs/`
- `logcat.txt` (14 МБ, полный logcat)
- `app_cache.log`, `project_app.log` (логи LogService)
- `setup_arm64.log`, `bootstrap_tail.log` (PRoot rootfs)

## Найденные проблемы

### 1. Phantom Process Killer убивает дочерние процессы PRoot (главная причина «тормозов»)

В logcat многократно:

```
ActivityManager: Killing PhantomProcessRecord {..:libproot.so/u0a170}: Trimming phantom processes
ActivityManager: Process PhantomProcessRecord {..} died
```

Android 12+ ограничивает число дочерних процессов фоновых приложений (~32). PRoot и
сборщики (Gradle/Java/Node/Dart) легко превышают лимит, после чего система их убивает.

Код `ShizukuBridge.boostForBuild()` отключал лимит **только через Shizuku**, но на этом
телефоне Shizuku недоступен:

```
[Shizuku] binder=false, permission=false, uid=-1
```

Поэтому защита не применялась ни при сборке, ни в простое.

**Исправления:**
- `lib/core/services/shizuku_bridge.dart`: добавлен fallback на `su` (Magisk/KernelSU/APatch),
  если Shizuku недоступен; команды `device_config put activity_manager max_phantom_processes
  2147483647`, `settings put global settings_enable_monitor_phantom_procs false`, whitelist
  и appops применяются через root.
- `lib/main.dart`: `boostForBuild()` вызывается сразу при старте приложения (не только перед
  сборкой), чтобы убийца процессов не трогал PRoot во время инициализации.

На устройстве настройки применены вручную через root:
`max_phantom_processes=2147483647`, `settings_enable_monitor_phantom_procs=false`.

### 2. Дублирование логов в logcat

`LogService._appendFormatted()` писал каждую строку ещё и в `stdout`, что дублирует все
сообщения в Android logcat (сотни строк во время сборки) и замедляет чтение логов/UI.

**Исправление:** `lib/core/services/log_service.dart` — вывод в `stdout` по умолчанию
отключён; включается явно через `--dart-define=QI_MIRROR_STDOUT=true`. Логи по-прежнему
пишутся в `app_cache.log` / `.quantum/app.log`, хранятся в памяти и транслируются в UI.

### 3. SELinux-отказы у libproot (не фатально, но шумно)

```
avc: denied { setattr } for name="/" dev="proc" ...
avc: denied { search } for name="tests" ... shell_test_data_file
avc: denied { setattr } for name="maps" ...
```

Типично для `untrusted_app` + PRoot. Для стабильной работы лучше использовать
«Своё ядро (Root)» вместо PRoot — тогда这些因素 исчезают.

### 4. Прочее

- `FrameTracker: force finish cuj, time out: J<IME_INSETS_HIDE_ANIMATION>` — задержка
  анимации скрытия клавиатуры (UI jank, не критично).
- `setup_arm64.log`: `quantum-heal-x64` настраивает x86_64 glibc/Box64 внутри arm64 PRoot.
  Это ожидаемо только для Flutter Release-сборок; в Root-режиме шаг не нужен.

## Дополнение: «диспетчер задач»_showing много процессов (20:13)

После создания проекта `test` и открытия диспетчера QuantumIDE в `ps` было 24 процесса,
принадлежащих IDE/PRoot. Ключевые:

```
98.9%  curl -fsSL http://archive.ubuntu.com/.../libc6_2.39-0ubuntu8.3_amd64.deb
       dartvm ... flutter_tools.snapshot --version ×4
       dartaotruntime ... analysis_server_aot.dart.snapshot --lsp ×3
       libproot.so ×3 (сессии терминала)
```

`curl` качал **amd64 glibc** на arm64‑устройстве — это `quantum-heal-x64`, который
`setups-arm64.sh` запускал **безусловно при каждом старте** setup. Он же дёргал
`apt-get install box64/qemu-user-static`, из-за чего плодились дочерние процессы,
которые затем убивал Phantom Process Killer.

**Исправление:** `lib/core/services/runtime_service.dart`
- убрал вызов `quantum-heal-x64` из блока починки AAPT2;
- перенес вызов `quantum-heal-x64` под условие реального Flutter Release-сборки
  (`/root/.quantum_flutter_release_requested` или `--force-x64`). Build-скрипты и так
  вызывают его перед release-сборкой, поэтому на старте он больше не нужен.

Мусорные процессы (curl + dartvm --version + осиротевшие LSP) были убиты через root:
число процессов IDE упало с 24 до 3, свободная ОЗУ выросла с 32 МБ до 153 МБ.

## Важно

GitHub-токен (`ghp_...`) был опубликован в чате. Репозиторий публичный, поэтому клонирование
выполнено **без** токена. Токен следует отозвать в GitHub Settings → Developer settings →
Personal access tokens и при необходимости выпустить новый.
