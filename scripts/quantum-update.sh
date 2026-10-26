#!/bin/bash
set -e

printf "\033[1;35m====================================================\033[0m\n"
printf "\033[1;36m  🚀 Quantum IDE: Автоматическое обновление & Настройка  \033[0m\n"
printf "\033[1;35m====================================================\033[0m\n\n"

# 1. Поиск последнего релиза
printf "\033[1;33m[1/3] Проверка свежих обновлений на GitHub...\033[0m\n"
LATEST_TAG=$(curl -s "https://api.github.com/repos/Lesorub361/quantum_ide/releases/latest" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$LATEST_TAG" ]; then
  LATEST_TAG="v1.2.76"
fi

printf "  Найден актуальный релиз: \033[1;32m%s\033[0m\n" "$LATEST_TAG"

# 2. Скачивание APK в папку «Загрузки» телефона
APK_URL="https://github.com/Lesorub361/quantum_ide/releases/download/${LATEST_TAG}/app-arm64-v8a-release.apk"
OUT_DIR="/storage/emulated/0/Download"
[ ! -d "$OUT_DIR" ] && OUT_DIR="/sdcard/Download"
[ ! -d "$OUT_DIR" ] && OUT_DIR="/tmp"

OUT_FILE="${OUT_DIR}/quantum-ide-${LATEST_TAG}.apk"
printf "\033[1;33m[2/3] Загрузка APK в папку Загрузки (%s)...\033[0m\n" "$OUT_FILE"

if curl -k -fL --retry 3 -o "$OUT_FILE" "$APK_URL"; then
  printf "  \033[1;32m✔ APK успешно загружен:\033[0m %s\n" "$OUT_FILE"
  # Создаем симлинк на latest
  ln -sf "$OUT_FILE" "${OUT_DIR}/quantum-ide-latest.apk" 2>/dev/null || true
else
  printf "  \033[1;31m✖ Не удалось скачать напрямую, ссылка:\033[0m %s\n" "$APK_URL"
fi

# 3. Лечение ограничений Dart SDK в pubspec.yaml проектов
printf "\033[1;33m[3/4] Проверка и исправление SDK ограничений в проектах...\033[0m\n"
if [ -d "/root/projects" ]; then
  find /root/projects -name "pubspec.yaml" 2>/dev/null | while read -r pfile; do
    if grep -qE "sdk:\s*(\^3\.1[3-9]|>=3\.1[3-9])" "$pfile" 2>/dev/null; then
      sed -i -E "s/sdk:\s*(\^3\.1[3-9][0-9.]*|>=3\.1[3-9][0-9.]*)/sdk: '>=3.12.0 <4.0.0'/g" "$pfile"
      printf "  \033[1;32m✔ Исправлен SDK constraint в:\033[0m %s\n" "$pfile"
    fi
  done
fi

# 4. Обновление Flutter & Dart SDK до 3.47.8 (Dart 3.13+)
printf "\033[1;33m[4/4] Проверка версии Flutter & Dart SDK...\033[0m\n"
if [ -d "/root/flutter/.git" ]; then
  CURR_DART=$(cat /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || echo "unknown")
  printf "  Текущая версия Dart: \033[1;36m%s\033[0m\n" "$CURR_DART"
  if ! echo "$CURR_DART" | grep -qE "3\.(1[3-9]|[2-9][0-9])"; then
    printf "  \033[1;33mОбновление Flutter до 3.47.8 (Dart 3.13+)...\033[0m\n"
    git -C /root/flutter config --global --add safe.directory '*' 2>/dev/null || true
    (git -C /root/flutter fetch --depth 1 origin tag 3.47.8 2>/dev/null || git -C /root/flutter fetch --tags origin 2>/dev/null || true)
    git -C /root/flutter checkout 3.47.8 -f 2>/dev/null || true
    /root/flutter/bin/flutter precache --android 2>/dev/null || true
    printf "  \033[1;32m✔ Flutter успешно обновлен до 3.47.8 (Dart 3.13+)!\033[0m\n"
  else
    printf "  \033[1;32m✔ Flutter SDK уже поддерживает Dart 3.13+\033[0m\n"
  fi
fi

printf "\n\033[1;32m🎉 Готово! Чтобы установить обновление, откройте файл:\033[0m\n"
printf "\033[1;36m   %s\033[0m (или в проводнике в папке Загрузки)\n" "$OUT_FILE"
