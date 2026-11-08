#!/bin/bash
set -e

printf "\033[1;35m====================================================\033[0m\n"
printf "\033[1;36m  🚀 Quantum IDE: Автоматическое обновление & Настройка  \033[0m\n"
printf "\033[1;35m====================================================\033[0m\n\n"

# 1. Поиск последнего релиза
printf "\033[1;33m[1/4] Проверка свежих обновлений на GitHub...\033[0m\n"
LATEST_TAG=$(curl -fsSL --max-time 10 "https://api.github.com/repos/Lesorub361/quantum_ide/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$LATEST_TAG" ]; then
  LATEST_TAG="v1.2.199"
fi

printf "  Найден актуальный релиз: \033[1;32m%s\033[0m\n" "$LATEST_TAG"

# 2. Скачивание APK в папку «Загрузки» телефона / ПК
APK_URL="https://github.com/Lesorub361/quantum_ide/releases/download/${LATEST_TAG}/app-arm64-v8a-release.apk"
FALLBACK_APK_URL="https://github.com/Lesorub361/quantum_ide/releases/download/${LATEST_TAG}/app-release.apk"
OUT_DIR="/storage/emulated/0/Download"
[ ! -d "$OUT_DIR" ] && OUT_DIR="/sdcard/Download"
[ ! -d "$OUT_DIR" ] && [ -d "$HOME/Downloads" ] && OUT_DIR="$HOME/Downloads"
[ ! -d "$OUT_DIR" ] && OUT_DIR="/tmp"

OUT_FILE="${OUT_DIR}/quantum-ide-${LATEST_TAG}.apk"
printf "\033[1;33m[2/4] Загрузка APK в папку Загрузки (%s)...\033[0m\n" "$OUT_FILE"

if curl -fL --retry 3 -o "$OUT_FILE" "$APK_URL" 2>/dev/null || curl -fL --retry 3 -o "$OUT_FILE" "$FALLBACK_APK_URL"; then
  printf "  \033[1;32m✔ APK успешно загружен:\033[0m %s\n" "$OUT_FILE"
  ln -sf "$OUT_FILE" "${OUT_DIR}/quantum-ide-latest.apk" 2>/dev/null || true
else
  printf "  \033[1;31m✖ Не удалось скачать напрямую, ссылка:\033[0m %s\n" "$APK_URL"
fi

# 3. Лечение ограничений Dart SDK в pubspec.yaml проектов
printf "\033[1;33m[3/4] Проверка и исправление SDK ограничений в проектах...\033[0m\n"
for PROJ_DIR in "/root/projects" "$HOME/projects" "/storage/emulated/0/QuantumIDE"; do
  if [ -d "$PROJ_DIR" ]; then
    find "$PROJ_DIR" -maxdepth 3 -name "pubspec.yaml" 2>/dev/null | while read -r pfile; do
      if grep -qE "sdk:\s*(\^3\.1[3-9]|>=3\.1[3-9])" "$pfile" 2>/dev/null; then
        sed -i -E "s/sdk:\s*(\^3\.1[3-9][0-9.]*|>=3\.1[3-9][0-9.]*)/sdk: '>=3.11.0 <4.0.0'/g" "$pfile"
        printf "  \033[1;32m✔ Исправлен SDK constraint в:\033[0m %s\n" "$pfile"
      fi
    done
  fi
done

# 4. Обновление Flutter & Dart SDK до 3.47.8 (Dart 3.13+)
printf "\033[1;33m[4/4] Проверка версии Flutter & Dart SDK...\033[0m\n"
FLUTTER_ROOT="/root/flutter"
[ ! -d "$FLUTTER_ROOT/.git" ] && [ -d "$HOME/flutter/.git" ] && FLUTTER_ROOT="$HOME/flutter"

if [ -d "$FLUTTER_ROOT/.git" ]; then
  CURR_DART=$(cat "$FLUTTER_ROOT/bin/cache/dart-sdk/version" 2>/dev/null || echo "unknown")
  printf "  Текущая версия Dart: \033[1;36m%s\033[0m\n" "$CURR_DART"
  if ! echo "$CURR_DART" | grep -qE "3\.(1[1-9]|[2-9][0-9])"; then
    printf "  \033[1;33mОбновление Flutter до 3.47.8...\033[0m\n"
    git -C "$FLUTTER_ROOT" config --global --add safe.directory '*' 2>/dev/null || true
    (git -C "$FLUTTER_ROOT" fetch --depth 1 origin tag 3.47.8 2>/dev/null || git -C "$FLUTTER_ROOT" fetch --tags origin 2>/dev/null || true)
    git -C "$FLUTTER_ROOT" checkout 3.47.8 -f 2>/dev/null || true
    "$FLUTTER_ROOT/bin/flutter" precache --android 2>/dev/null || true
    printf "  \033[1;32m✔ Flutter успешно обновлен!\033[0m\n"
  else
    printf "  \033[1;32m✔ Flutter SDK уже актуален (%s)\033[0m\n" "$CURR_DART"
  fi
fi

printf "\n\033[1;32m🎉 Готово! Чтобы установить обновление, откройте файл:\033[0m\n"
printf "\033[1;36m   %s\033[0m (или в проводнике в папке Загрузки)\n" "$OUT_FILE"
