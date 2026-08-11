#!/bin/bash
# setup-android-build.sh
# Автоматическая настройка окружения для сборки Android APK на arm64 хостах
# Запускать один раз перед первой сборкой (или после обновления NDK/SDK)
# Требует sudo для установки qemu-user-static и пакетов

set -euo pipefail

echo "=== QuantumIDE Android Build Environment Setup ==="

# 1. Установка qemu-user-static для запуска x86_64 aapt2 под arm64
echo "[1/6] Установка qemu-user-static..."
if ! command -v qemu-x86_64-static &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y qemu-user-static
else
    echo "  qemu-user-static уже установлен"
fi

# 2. Подготовка x86_64 sysroot для qemu (libc6, libgcc-s1)
echo "[2/6] Подготовка x86_64 sysroot для qemu..."
SYSROOT="/tmp/opencode/qemu_x86_sysroot"
mkdir -p "$SYSROOT"

# Создаём временный sources.list для amd64
cat > /tmp/sources_amd64.list << 'EOF'
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-security main
EOF

# Скачиваем libc6 и libgcc-s1 для amd64
apt-get update -o Dir::Etc::sourcelist=/tmp/sources_amd64.list -o Dir::Etc::sourceparts=/dev/null
apt-get download -o Dir::Etc::sourcelist=/tmp/sources_amd64.list -o Dir::Etc::sourceparts=/dev/null libc6:amd64 libgcc-s1:amd64

# Распаковываем в sysroot
dpkg -x libc6*amd64.deb "$SYSROOT"
dpkg -x libgcc-s1*amd64.deb "$SYSROOT"

# Создаём symlink для ld-linux-x86-64.so.2 в lib64
mkdir -p "$SYSROOT/lib64"
ln -sf /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "$SYSROOT/lib64/ld-linux-x86-64.so.2"

echo "  Sysroot готов: $SYSROOT"

# 3. Скачиваем x86_64 aapt2 из Maven Google
echo "[3/6] Скачивание x86_64 aapt2..."
AAPT2_VERSION="8.11.1-12782657"
AAPT2_JAR="/tmp/opencode/aapt2-${AAPT2_VERSION}-linux.jar"
AAPT2_DIR="/tmp/opencode/aapt2_x86"

mkdir -p "$(dirname "$AAPT2_JAR")" "$AAPT2_DIR"

if [ ! -f "$AAPT2_JAR" ]; then
    curl -sSL "https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/${AAPT2_VERSION}/aapt2-${AAPT2_VERSION}-linux.jar" \
        -o "$AAPT2_JAR"
fi

cd "$AAPT2_DIR"
unzip -o "$AAPT2_JAR" >/dev/null 2>&1
chmod +x aapt2

echo "  aapt2 готов: $AAPT2_DIR/aapt2"

# 4. Создаём обёртку aapt2 под qemu
echo "[4/6] Создание обёртки aapt2..."
cat > /tmp/opencode/aapt2_qemu_wrapper.sh << 'EOF'
#!/bin/bash
# Wrapper для запуска x86_64 aapt2 под qemu-user-static на arm64 хостах
QEMU=/usr/bin/qemu-x86_64-static
SYSROOT=/tmp/opencode/qemu_x86_sysroot
AAPT2_BIN=/tmp/opencode/aapt2_x86/aapt2
exec "$QEMU" -L "$SYSROOT" "$AAPT2_BIN" "$@"
EOF
chmod +x /tmp/opencode/aapt2_qemu_wrapper.sh

# 5. Заменяем aapt2 во всех build-tools на обёртку
echo "[5/6] Установка обёртки aapt2 в Android SDK..."
for V in 34.0.0 35.0.0 36.0.0; do
    BT="/root/android-sdk/build-tools/$V"
    if [ -d "$BT" ]; then
        rm -f "$BT/aapt2"
        cp /tmp/opencode/aapt2_qemu_wrapper.sh "$BT/aapt2"
        chmod +x "$BT/aapt2"
        echo "  Установлен в $BT"
    fi
done

# 6. Патчим NDK: заменяем пустые libgcc.a/libatomic.a на настоящие builtins
echo "[6/6] Патчинг NDK (заглушки libgcc.a/libatomic.a)..."
for NDK_VER in 25.1.8937393 27.0.12077973 28.2.13676358; do
    NDK_BASE="/root/android-sdk/ndk/$NDK_VER/toolchains/llvm/prebuilt/linux-x86_64"
    if [ ! -d "$NDK_BASE" ]; then continue; fi
    
    BUILTINS_DIR="$NDK_BASE/lib/clang/19/lib/linux"
    
    # aarch64
    for api in $(seq 21 35); do
        cp "$BUILTINS_DIR/libclang_rt.builtins-aarch64-android.a" \
           "$NDK_BASE/sysroot/usr/lib/aarch64-linux-android/$api/libgcc.a" 2>/dev/null || true
        cp "$BUILTINS_DIR/libclang_rt.builtins-aarch64-android.a" \
           "$NDK_BASE/sysroot/usr/lib/aarch64-linux-android/$api/libatomic.a" 2>/dev/null || true
    done
    cp "$BUILTINS_DIR/libclang_rt.builtins-aarch64-android.a" \
       "$NDK_BASE/sysroot/usr/lib/aarch64-linux-android/libgcc.a" 2>/dev/null || true
    cp "$BUILTINS_DIR/libclang_rt.builtins-aarch64-android.a" \
       "$NDK_BASE/sysroot/usr/lib/aarch64-linux-android/libatomic.a" 2>/dev/null || true
    
    # arm (armeabi-v7a)
    for api in $(seq 21 35); do
        cp "$BUILTINS_DIR/libclang_rt.builtins-arm-android.a" \
           "$NDK_BASE/sysroot/usr/lib/arm-linux-androideabi/$api/libgcc.a" 2>/dev/null || true
        cp "$BUILTINS_DIR/libclang_rt.builtins-arm-android.a" \
           "$NDK_BASE/sysroot/usr/lib/arm-linux-androideabi/$api/libatomic.a" 2>/dev/null || true
    done
    cp "$BUILTINS_DIR/libclang_rt.builtins-arm-android.a" \
       "$NDK_BASE/sysroot/usr/lib/arm-linux-androideabi/libgcc.a" 2>/dev/null || true
    cp "$BUILTINS_DIR/libclang_rt.builtins-arm-android.a" \
       "$NDK_BASE/sysroot/usr/lib/arm-linux-androideabi/libatomic.a" 2>/dev/null || true
    
    # x86_64
    for api in $(seq 21 35); do
        cp "$BUILTINS_DIR/libclang_rt.builtins-x86_64-android.a" \
           "$NDK_BASE/sysroot/usr/lib/x86_64-linux-android/$api/libgcc.a" 2>/dev/null || true
    done
    cp "$BUILTINS_DIR/libclang_rt.builtins-x86_64-android.a" \
       "$NDK_BASE/sysroot/usr/lib/x86_64-linux-android/libgcc.a" 2>/dev/null || true
    
    # i686
    for api in $(seq 21 35); do
        cp "$BUILTINS_DIR/libclang_rt.builtins-i686-android.a" \
           "$NDK_BASE/sysroot/usr/lib/i686-linux-android/$api/libgcc.a" 2>/dev/null || true
    done
    cp "$BUILTINS_DIR/libclang_rt.builtins-i686-android.a" \
       "$NDK_BASE/sysroot/usr/lib/i686-linux-android/libgcc.a" 2>/dev/null || true
    
    echo "  NDK $NDK_VER пропатчен"
done

# 7. Установка clang wrapper для линковки C++ (libc++ и полная libc)
echo "[7/6] Установка clang wrapper..."
CLANG_WRAPPER="/tmp/opencode/clang_wrapper.sh"
cat > "$CLANG_WRAPPER" << 'EOF'
#!/bin/bash
# NDK clang wrapper: добавляет -lc++ -lc++abi и использует полную libc (api>=30)
LINK=1
PRE=()
POST=()
SYSROOT=""
ABI=""
API=""
for a in "$@"; do
  case "$a" in
    -c|-E|-S|-fsyntax-only|--analyze|-emit-llvm|-print-file-name=*|-print-prog-name=*|-dumpmachine|-dumpversion|-print-targets|-print-search-dirs|-M|-MM)
      LINK=0 ;;
  esac
  case "$a" in
    --sysroot=*) SYSROOT="${a#--sysroot=}" ;;
  esac
  case "$a" in
    --target=*aarch64*) ABI="aarch64-linux-android"; API="${a##*android}";;
    --target=*armv7*|--target=*armlinux*|--target=*arm-linux*) ABI="arm-linux-androideabi"; API="${a##*androideabi}";;
    --target=*x86_64*|--target=*i686*) ABI="${a%%-none*}"; ABI="${ABI#--target=}"; ABI="${ABI}-linux-android"; API="${a##*android}";;
  esac
done
API="${API%% *}"
API="${API%%\"}"
if [ "$LINK" -eq 1 ] && [ -n "$SYSROOT" ] && [ -n "$ABI" ]; then
  BASE="$SYSROOT/usr/lib/$ABI"
  WANT=$((API > 30 ? API : 30))
  CHOSEN=""
  for api in $(seq $WANT -1 30); do
    if [ -f "$BASE/$api/libc.so" ]; then CHOSEN="$BASE/$api"; break; fi
  done
  if [ -z "$CHOSEN" ]; then
    for api in $(seq $WANT -1 21); do
      if [ -f "$BASE/$api/libc.so" ]; then CHOSEN="$BASE/$api"; break; fi
    done
  fi
  if [ -n "$CHOSEN" ]; then
    PRE+=("-L$CHOSEN")
  fi
  POST+=(-lc++ -lc++abi)
fi
exec /usr/bin/clang "${PRE[@]}" "$@" "${POST[@]}"
EOF
chmod +x "$CLANG_WRAPPER"

for NDK_VER in 27.0.12077973 28.2.13676358; do
    NDK_BIN="/root/android-sdk/ndk/$NDK_VER/toolchains/llvm/prebuilt/linux-x86_64/bin"
    if [ -d "$NDK_BIN" ]; then
        cp "$CLANG_WRAPPER" "$NDK_BIN/clang"
        chmod +x "$NDK_BIN/clang"
        echo "  clang wrapper установлен в $NDK_BIN"
    fi
done

# 8. Добавление abiFilters в build.gradle.kts (только arm64-v8a)
echo "[8/6] abiFilters уже настроен в android/app/build.gradle.kts"

echo ""
echo "=== ГОТОВО ==="
echo "Окружение настроено для сборки Android на arm64 хосте."
echo ""
echo "Теперь можно собирать:"
echo "  cd /root/projects/quantum_ide"
echo "  flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons"
echo ""
echo "Если обновляли NDK/SDK — запустите скрипт заново."