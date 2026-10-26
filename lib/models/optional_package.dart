import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class OptionalPackage {
  final String id;
  final String name;
  final String description;
  final String command;
  final IconData icon;
  final String category;
  final String? version;
  bool isInstalled;
  bool isInstalling;

  OptionalPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.command,
    required this.icon,
    this.category = 'Tools',
    this.version,
    this.isInstalled = false,
    this.isInstalling = false,
  });
}

const String _aptPrefix = 'export HOME=/root ; export USER=root ; export DEBIAN_FRONTEND=noninteractive ; '
    'kill -9 \$(pgrep -x "apt|apt-get|dpkg|dpkg-deb" 2>/dev/null) 2>/dev/null ; '
    'rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null ; '
    'dpkg --configure -a 2>/dev/null ; '
    '(apt-get update -o Acquire::Retries=1 2>/dev/null || apt update 2>/dev/null || true) ; '
    'apt-get install -y --no-install-recommends ca-certificates 2>/dev/null || true ; ';

const String _ensureCmdlineTools = '(if [ ! -f /root/android-sdk/cmdline-tools/latest/bin/sdkmanager ]; then '
    'mkdir -p /root/android-sdk/cmdline-tools /tmp/cmdline-extracted && '
    'apt-get update 2>/dev/null && apt-get install -y --no-install-recommends wget curl unzip openjdk-17-jdk-headless ca-certificates 2>/dev/null && '
    '(wget --no-check-certificate -qO /tmp/cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip || curl -k -fL --retry 3 -o /tmp/cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip) && '
    'rm -rf /root/android-sdk/cmdline-tools/latest && '
    'unzip -qo /tmp/cmdline-tools.zip -d /tmp/cmdline-extracted && '
    'mkdir -p /root/android-sdk/cmdline-tools/latest && '
    '(if [ -d /tmp/cmdline-extracted/cmdline-tools ]; then cp -r /tmp/cmdline-extracted/cmdline-tools/* /root/android-sdk/cmdline-tools/latest/; else cp -r /tmp/cmdline-extracted/* /root/android-sdk/cmdline-tools/latest/; fi) && '
    'chmod +x /root/android-sdk/cmdline-tools/latest/bin/* 2>/dev/null || true && '
    'rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-extracted; fi) && '
    '[ -f /root/android-sdk/cmdline-tools/latest/bin/sdkmanager ]';

const String _sdkPrefix = '$_ensureCmdlineTools && '
    'export JAVA_HOME=\${JAVA_HOME:-\$(ls -d /usr/lib/jvm/java-17-openjdk-* /usr/lib/jvm/java-21-openjdk-* /usr/lib/jvm/java-*-openjdk-* 2>/dev/null | head -n 1)} && '
    'export PATH=\$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:\$PATH && '
    'mkdir -p /root/android-sdk/licenses && '
    '(printf "24333f8a63b6825ea9c5514f83c2829b004d1fee\\nd56f5187479451eabf01fb78af6dfcb131a6481e\\n2fa2d150aa0a1204d10e5ed57ab8369e7b50077c\\n" > /root/android-sdk/licenses/android-sdk-license 2>/dev/null || true) && '
    '(printf "84831b9409646a918e30573bab4c9c91346d8abd\\n" > /root/android-sdk/licenses/android-sdk-preview-license 2>/dev/null || true) && '
    '(printf "859f317696f67ef3d7f30a50a5560e7834b43903\\n" > /root/android-sdk/licenses/android-sdk-arm-dbt-license 2>/dev/null || true) && '
    '(yes 2>/dev/null | /root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk --licenses >/dev/null 2>&1 || true) && '
    '/root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk';

String _cmakeArm64Command(String version, String sdkDirName) {
  return '${_aptPrefix}apt install -y curl wget tar ninja-build ca-certificates && '
      'mkdir -p /opt/cmake-$version /root/android-sdk/cmake/$sdkDirName/bin && '
      '(curl -k -fL --retry 3 -o /tmp/cmake.tar.gz "https://github.com/Kitware/CMake/releases/download/v$version/cmake-$version-linux-aarch64.tar.gz" || '
      'wget --no-check-certificate -qO /tmp/cmake.tar.gz "https://github.com/Kitware/CMake/releases/download/v$version/cmake-$version-linux-aarch64.tar.gz") && '
      'tar -xzf /tmp/cmake.tar.gz --strip-components=1 -C /opt/cmake-$version && '
      'rm -f /tmp/cmake.tar.gz && '
      'ln -sf /opt/cmake-$version/bin/cmake /usr/local/bin/cmake && '
      'ln -sf /opt/cmake-$version/bin/cmake /usr/bin/cmake && '
      'printf "#!/bin/bash\\n/usr/local/bin/quantum-patch-ndk --fast 2>/dev/null || true\\nexec /opt/cmake-$version/bin/cmake \\"\\\$@\\"\\n" > /root/android-sdk/cmake/$sdkDirName/bin/cmake && '
      'chmod +x /root/android-sdk/cmake/$sdkDirName/bin/cmake && '
      'ln -sf /usr/bin/ninja /root/android-sdk/cmake/$sdkDirName/bin/ninja && '
      'printf "Pkg.Desc = CMake $version\\nPkg.Revision = $version\\n" > /root/android-sdk/cmake/$sdkDirName/source.properties && '
      '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && '
      'echo "CMake $version (ARM64 native) successfully configured"';
}

String _ndkArm64Command({
  required String versionDir,
  required String primaryUrl,
  required String fallbackUrl,
  required String aliasName,
}) {
  return '${_aptPrefix}apt install -y --no-install-recommends curl wget tar xz-utils ca-certificates && '
      'mkdir -p /root/android-sdk/ndk/$versionDir && '
      'echo "Downloading Android NDK ($versionDir ARM64 native)..." && '
      '(curl -k -fL --retry 3 -o /tmp/ndk.tar.xz "$primaryUrl" || '
      'wget --no-check-certificate -qO /tmp/ndk.tar.xz "$primaryUrl" || '
      'curl -k -fL --retry 3 -o /tmp/ndk.tar.xz "$fallbackUrl" || '
      'wget --no-check-certificate -qO /tmp/ndk.tar.xz "$fallbackUrl") && '
      'echo "Extracting NDK to /root/android-sdk/ndk/$versionDir..." && '
      'tar -xf /tmp/ndk.tar.xz --strip-components=1 -C /root/android-sdk/ndk/$versionDir/ && '
      'rm -f /tmp/ndk.tar.xz && '
      '(if [ -d "/root/android-sdk/ndk/$versionDir/toolchains/llvm/prebuilt/linux-arm64" ]; then '
      'ln -sfn linux-arm64 /root/android-sdk/ndk/$versionDir/toolchains/llvm/prebuilt/linux-x86_64 2>/dev/null || true; '
      'ln -sfn linux-arm64 /root/android-sdk/ndk/$versionDir/toolchains/llvm/prebuilt/linux-aarch64 2>/dev/null || true; '
      'elif [ -d "/root/android-sdk/ndk/$versionDir/toolchains/llvm/prebuilt/linux-aarch64" ]; then '
      'ln -sfn linux-aarch64 /root/android-sdk/ndk/$versionDir/toolchains/llvm/prebuilt/linux-x86_64 2>/dev/null || true; '
      'ln -sfn linux-aarch64 /root/android-sdk/ndk/$versionDir/toolchains/llvm/prebuilt/linux-arm64 2>/dev/null || true; '
      'fi) && '
      'chmod +x /root/android-sdk/ndk/$versionDir/ndk-build /root/android-sdk/ndk/$versionDir/toolchains/llvm/prebuilt/*/bin/* 2>/dev/null || true && '
      'ln -sfn "$versionDir" "/root/android-sdk/ndk/$aliasName" 2>/dev/null || true && '
      '(if [ ! -f "/root/android-sdk/ndk/$versionDir/source.properties" ]; then '
      'printf "Pkg.Desc = Android NDK\\nPkg.Revision = $versionDir\\n" > "/root/android-sdk/ndk/$versionDir/source.properties"; '
      'fi) && '
      'echo "Android NDK ($versionDir ARM64) successfully installed!"';
}

String _sdkToolsArm64Command() {
  return '${_aptPrefix}apt install -y --no-install-recommends curl wget unzip ca-certificates && '
      'mkdir -p /root/android-sdk/build-tools/36.0.0 /root/android-sdk/build-tools/35.0.1 /root/android-sdk/build-tools/35.0.0 /root/android-sdk/build-tools/34.0.0 /tmp/sdk_tools && '
      '(if [ ! -f /root/android-sdk/build-tools/34.0.0/core-lambda-stubs.jar ]; then '
      '($_sdkPrefix "build-tools;34.0.0" "platforms;android-34" || true); fi) && '
      'echo "Downloading Android SDK Build-Tools (ARM64 static)..." && '
      '(curl -k -fL --retry 3 -o /tmp/sdk-tools.zip "https://github.com/Lesorub361/quantum_ide/releases/download/v1.2.32/android-sdk-tools-static-aarch64.zip" || '
      'wget --no-check-certificate -qO /tmp/sdk-tools.zip "https://github.com/Lesorub361/quantum_ide/releases/download/v1.2.32/android-sdk-tools-static-aarch64.zip" || '
      'curl -k -fL --retry 3 -o /tmp/sdk-tools.zip "https://github.com/lzhiyong/android-sdk-tools/releases/download/35.0.2/android-sdk-tools-static-aarch64.zip" || '
      'wget --no-check-certificate -qO /tmp/sdk-tools.zip "https://github.com/lzhiyong/android-sdk-tools/releases/download/35.0.2/android-sdk-tools-static-aarch64.zip") && '
      'unzip -qo /tmp/sdk-tools.zip -d /tmp/sdk_tools && '
      'cp -rf /tmp/sdk_tools/build-tools/* /root/android-sdk/build-tools/36.0.0/ 2>/dev/null || true && '
      'cp -rf /tmp/sdk_tools/build-tools/* /root/android-sdk/build-tools/35.0.1/ 2>/dev/null || true && '
      'cp -rf /tmp/sdk_tools/build-tools/* /root/android-sdk/build-tools/35.0.0/ 2>/dev/null || true && '
      'cp -rf /tmp/sdk_tools/build-tools/* /root/android-sdk/build-tools/34.0.0/ 2>/dev/null || true && '
      '(if [ -d /root/android-sdk/build-tools/34.0.0/lib ]; then '
      'for ver in 35.0.0 35.0.1 36.0.0; do '
      'cp -rn /root/android-sdk/build-tools/34.0.0/* "/root/android-sdk/build-tools/\$ver/" 2>/dev/null || true; '
      'printf "Pkg.UserSrc=false\\nPkg.Revision=%s\\n" "\$ver" > "/root/android-sdk/build-tools/\$ver/source.properties"; '
      'done; fi) && '
      '(if [ -d /root/android-sdk/platforms/android-34 ]; then '
      'for api in 35 36; do '
      'if [ ! -f "/root/android-sdk/platforms/android-\$api/android.jar" ]; then '
      'mkdir -p "/root/android-sdk/platforms/android-\$api"; '
      'cp -rn /root/android-sdk/platforms/android-34/* "/root/android-sdk/platforms/android-\$api/" 2>/dev/null || true; '
      'sed -i "s/AndroidVersion.ApiLevel=34/AndroidVersion.ApiLevel=\$api/g" "/root/android-sdk/platforms/android-\$api/source.properties" 2>/dev/null || true; '
      'sed -i "s/ro.build.version.sdk=34/ro.build.version.sdk=\$api/g" "/root/android-sdk/platforms/android-\$api/build.prop" 2>/dev/null || true; '
      'fi; done; fi) && '
      '(cp -f /tmp/sdk_tools/build-tools/aapt2 /usr/bin/aapt2 2>/dev/null || true) && '
      '(cp -f /tmp/sdk_tools/build-tools/aapt /usr/bin/aapt 2>/dev/null || true) && '
      '(cp -f /tmp/sdk_tools/build-tools/zipalign /usr/bin/zipalign 2>/dev/null || true) && '
      '(cp -f /tmp/sdk_tools/build-tools/aidl /usr/bin/aidl 2>/dev/null || true) && '
      '(cp -f /tmp/sdk_tools/platform-tools/adb /usr/bin/adb 2>/dev/null || true) && '
      '(cp -f /tmp/sdk_tools/platform-tools/fastboot /usr/bin/fastboot 2>/dev/null || true) && '
      'chmod +x /usr/bin/aapt2 /usr/bin/aapt /usr/bin/zipalign /usr/bin/aidl /usr/bin/adb /usr/bin/fastboot /root/android-sdk/build-tools/*/* 2>/dev/null || true && '
      'rm -rf /tmp/sdk-tools.zip /tmp/sdk_tools && '
      'echo "Android SDK Build-Tools & Platform-Tools (ARM64 static) successfully installed!"';
}

String _rustArm64Command() {
  return '${_aptPrefix}apt install -y curl build-essential ca-certificates && '
      '(which rustc >/dev/null 2>&1 || (curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-host aarch64-unknown-linux-gnu)) && '
      'export PATH="\$HOME/.cargo/bin:\$PATH" && '
      'rustup target add aarch64-linux-android armv7-linux-androideabi 2>/dev/null || true && '
      'cargo --version && rustc --version && '
      'echo "Rust & Cargo ARM64 with Android targets successfully configured!"';
}

String _moldLinkerCommand() {
  return '${_aptPrefix}apt install -y mold clang lld ca-certificates && '
      '(ln -sf /usr/bin/mold /usr/local/bin/ld 2>/dev/null || true) && '
      'mold --version && '
      'echo "High-speed Mold linker (ARM64) successfully enabled!"';
}

final defaultPackages = [
  OptionalPackage(
    id: 'python',
    name: 'Python 3',
    version: '3.12',
    description: 'General-purpose programming language (python3, pip, venv)',
    command: '${_aptPrefix}apt install -y python3 python3-pip python3-venv python-is-python3',
    icon: LucideIcons.terminal,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'nodejs',
    name: 'Node.js & npm (LTS)',
    version: '20.x LTS',
    description: 'JavaScript runtime and npm package manager for modern tools and CLI',
    command: 'if which node >/dev/null 2>&1 && which npm >/dev/null 2>&1; then echo "Node.js & npm already installed: \$(node -v), npm \$(npm -v)"; else echo "Installing Node.js (found: \$(node -v 2>/dev/null || echo none))"; ${_aptPrefix}apt install -y curl ca-certificates && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x || curl -fsSL https://deb.nodesource.com/setup_20.x) | bash - && apt install -y nodejs; hash -r; node -v; fi',
    icon: LucideIcons.globe,
    category: 'Web',
  ),
  OptionalPackage(
    id: 'git',
    name: 'Git',
    version: '2.43+',
    description: 'Distributed version control system',
    command: '${_aptPrefix}apt install -y git ca-certificates',
    icon: LucideIcons.git_branch,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'git-lfs',
    name: 'Git LFS (Large File Storage)',
    version: '3.5+',
    description: 'Git extension for versioning large assets, APKs, and AI model weights',
    command: '${_aptPrefix}apt install -y git git-lfs && git lfs install',
    icon: LucideIcons.hard_drive_download,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'flutter',
    name: 'Flutter & Dart SDK (Verified 3.44.9)',
    version: '3.44.9',
    description: 'Google\'s UI toolkit for building natively compiled Dart and Flutter applications. Pinned to 3.44.9 for guaranteed ARM64 stability and black-screen prevention.',
    command: '${_aptPrefix}apt install -y git curl unzip xz-utils libglu1-mesa debianutils ca-certificates && git config --global --add safe.directory \'*\' 2>/dev/null || true && rm -f /root/flutter/.git/*.lock 2>/dev/null || true && if [ -d /root/flutter/.git ]; then cd /root/flutter && git fetch --depth 1 origin tag 3.44.9 2>/dev/null || git fetch --tags origin 2>/dev/null || true && git checkout 3.44.9 -f && /root/flutter/bin/flutter precache --android; else rm -rf /root/flutter && git clone --depth 1 --branch 3.44.9 https://github.com/flutter/flutter.git /root/flutter && /root/flutter/bin/flutter precache --android; fi && ln -sf /root/flutter/bin/flutter /usr/local/bin/flutter 2>/dev/null || true && ln -sf /root/flutter/bin/dart /usr/local/bin/dart 2>/dev/null || true && (grep -q "/root/flutter/bin" /root/.bashrc 2>/dev/null || echo "export PATH=\\\$PATH:/root/flutter/bin" >> /root/.bashrc) && (grep -q "/root/flutter/bin" /root/.profile 2>/dev/null || echo "export PATH=\\\$PATH:/root/flutter/bin" >> /root/.profile) && (/bin/bash /root/setup-arm64.sh 2>/dev/null || true)',
    icon: LucideIcons.smartphone,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'flutter-upgrade-3.47',
    name: 'Flutter & Dart SDK (Обновление до 3.47.8 / Dart 3.13+)',
    version: '3.47.8',
    description: 'Обновляет Flutter до 3.47.8 и Dart SDK до 3.13.0+. Устраняет ошибку «requires SDK version ^3.13.0, version solving failed».',
    command: '${_aptPrefix}apt install -y git curl unzip xz-utils libglu1-mesa debianutils ca-certificates && git config --global --add safe.directory \'*\' 2>/dev/null || true && rm -f /root/flutter/.git/*.lock 2>/dev/null || true && if [ -d /root/flutter/.git ]; then cd /root/flutter && (git fetch --depth 1 origin tag 3.47.8 2>/dev/null || git fetch --tags origin 2>/dev/null || true) && git checkout 3.47.8 -f && /root/flutter/bin/flutter precache --android; else rm -rf /root/flutter && git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git /root/flutter && /root/flutter/bin/flutter precache --android; fi && ln -sf /root/flutter/bin/flutter /usr/local/bin/flutter 2>/dev/null || true && ln -sf /root/flutter/bin/dart /usr/local/bin/dart 2>/dev/null || true && (/bin/bash /root/setup-arm64.sh 2>/dev/null || true) && flutter --version && echo "Flutter 3.47.8 & Dart 3.13.0+ успешно установлены!"',
    icon: LucideIcons.arrow_up,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'antigravity-cli',
    name: 'Antigravity CLI (agy)',
    version: '1.3.4',
    description: 'Official CLI tool for Google Antigravity AI models and autonomous agent orchestration',
    command: '${_aptPrefix}apt install -y curl tar gzip && ARCH=\$(uname -m) && if [ "\$ARCH" = "aarch64" ] || [ "\$ARCH" = "arm64" ]; then URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-arm/cli_linux_arm64.tar.gz"; else URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-x64/cli_linux_x64.tar.gz"; fi && mkdir -p /tmp/agy_dl && curl -fL --retry 3 "\$URL" | tar -xz -C /tmp/agy_dl && mkdir -p /usr/local/bin && mv /tmp/agy_dl/antigravity /usr/local/bin/agy && ln -sf /usr/local/bin/agy /usr/local/bin/antigravity && chmod +x /usr/local/bin/agy && rm -rf /tmp/agy_dl && echo "Antigravity CLI installed successfully"',
    icon: LucideIcons.sparkles,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'claude-code',
    name: 'Claude Code CLI (claude)',
    version: 'Latest',
    description: 'Anthropic\'s autonomous coding assistant CLI with full terminal execution and file editing',
    command: 'if which npm >/dev/null 2>&1; then (npm install -g @anthropic-ai/claude-code || sudo npm install -g @anthropic-ai/claude-code); else ${_aptPrefix}apt install -y curl && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs) && (npm install -g @anthropic-ai/claude-code || sudo npm install -g @anthropic-ai/claude-code); fi && (ln -sf /usr/local/lib/nodejs/bin/claude /usr/local/bin/claude 2>/dev/null || true)',
    icon: LucideIcons.bot,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'deepseek-harness',
    name: 'DeepSeek Harness CLI (dsh)',
    version: '0.2.0',
    description: 'DeepSeek autonomous agent runner for complex refactoring, reasoning, and test generation',
    command: '${_aptPrefix}apt install -y curl && (which node >/dev/null 2>&1 || (curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs)) && npm install -g @deepseek-ai/dsh && (ln -sf /usr/local/lib/nodejs/bin/dsh /usr/local/bin/dsh 2>/dev/null || true) && (ln -sf /usr/local/lib/nodejs/bin/deepseek-harness /usr/local/bin/deepseek-harness 2>/dev/null || true) && node -e "const fs = require(\'fs\'); const f1 = \'/usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/node-addon-system/lib/flock.js\'; if (fs.existsSync(f1)) { let s = fs.readFileSync(f1, \'utf8\'); s = s.replace(/loadBinding\\(\\)\\.tryLock\\(fd,\\s*resolve\\);/, \'resolve(0);\'); fs.writeFileSync(f1, s); } const f2 = \'/usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js\'; if (fs.existsSync(f2)) { let s = fs.readFileSync(f2, \'utf8\'); s = s.replace(\'await link(tmp, finalPath);\', \'await copyFile(tmp, finalPath, 1);\'); fs.writeFileSync(f2, s); } const f3 = \'/usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-fs-local/lib/index.js\'; if (fs.existsSync(f3)) { let s = fs.readFileSync(f3, \'utf8\'); s = s.replace(\'await linkFile(tempPath, absolutePath);\', \'await copyFile(tempPath, absolutePath, 1);\'); fs.writeFileSync(f3, s); }" && echo "DeepSeek Harness installed successfully"',
    icon: LucideIcons.brain_circuit,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'ollama-cli',
    name: 'Ollama CLI',
    version: 'Latest',
    description: 'Run large language models locally (Llama 3, Mistral, Qwen, etc.)',
    command: '${_aptPrefix}apt install -y curl && curl -fsSL https://ollama.com/install.sh | sh',
    icon: LucideIcons.brain,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'kilocode-cli',
    name: 'KiloCode CLI',
    version: 'Latest',
    description: 'Command-line interface for KiloCode development',
    command: 'if which npm >/dev/null 2>&1; then (npm install -g @kilocode/cli || sudo npm install -g @kilocode/cli); else ${_aptPrefix}apt install -y curl && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && (npm install -g @kilocode/cli || sudo npm install -g @kilocode/cli); fi && (ln -sf /usr/local/lib/nodejs/bin/kilocode /usr/local/bin/kilocode 2>/dev/null || true)',
    icon: LucideIcons.code,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'opencode-ai',
    name: 'OpenCode AI',
    version: 'Latest',
    description: 'AI-powered coding assistant and tools',
    command: 'if which npm >/dev/null 2>&1; then (npm i -g opencode-ai || sudo npm i -g opencode-ai) && (curl -4 -fsSL https://opencode.ai/install | bash || true); else ${_aptPrefix}apt install -y curl && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && (npm i -g opencode-ai || sudo npm i -g opencode-ai) && (curl -4 -fsSL https://opencode.ai/install | bash || true); fi && (ln -sf /usr/local/lib/nodejs/bin/opencode /usr/local/bin/opencode 2>/dev/null || true) && (ln -sf /usr/local/lib/nodejs/bin/opencode-ai /usr/local/bin/opencode-ai 2>/dev/null || true)',
    icon: LucideIcons.brain_circuit,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'local-ai-qwen',
    name: 'Local Llama Server',
    version: 'b11541',
    description: 'Local engine to run offline AI models (llama-server and llama-cli).',
    command: '${_aptPrefix}apt install -y curl wget tar ca-certificates && ARCH=\$(uname -m) && if [ "\$ARCH" = "aarch64" ] || [ "\$ARCH" = "arm64" ]; then LLAMA_ARCH="arm64"; else LLAMA_ARCH="x64"; fi && mkdir -p /tmp/llama_dl && cd /tmp/llama_dl && (wget --no-check-certificate -qO llama.tar.gz "https://github.com/ggml-org/llama.cpp/releases/download/b11541/llama-b11541-bin-ubuntu-\${LLAMA_ARCH}.tar.gz" || curl -k -fL --retry 3 -o llama.tar.gz "https://github.com/ggml-org/llama.cpp/releases/download/b11541/llama-b11541-bin-ubuntu-\${LLAMA_ARCH}.tar.gz") && tar -xzf llama.tar.gz && (find . -type f -name "llama-server" -exec cp {} /usr/bin/llama-server \\; ; find . -type f -name "llama-cli" -exec cp {} /usr/bin/llama-cli \\; ; find . \\( -name "*.so*" \\) -exec cp -a {} /usr/lib/ \\; 2>/dev/null || true ; find . \\( -name "*.so*" \\) -exec cp -a {} /usr/local/lib/ \\; 2>/dev/null || true ; ldconfig 2>/dev/null || true) && chmod +x /usr/bin/llama-server /usr/bin/llama-cli 2>/dev/null || true && cd / && rm -rf /tmp/llama_dl && echo "Llama Server installed successfully"',
    icon: LucideIcons.brain,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'build-essential',
    name: 'C++ Build Tools (GCC / Clang)',
    version: '13.x',
    description: 'GCC, G++, Make, and essential headers for C/C++ and native plugin compilation',
    command: '${_aptPrefix}apt update && apt install -y build-essential pkg-config',
    icon: LucideIcons.hammer,
    category: 'System',
  ),
  OptionalPackage(
    id: 'android-sdk',
    name: 'Android SDK & Java 17',
    version: 'API 34 + JDK 17',
    description: 'Essential for Android builds (Java 17, cmdline-tools, platform-tools, Android 34)',
    command: '${_aptPrefix}apt install -y openjdk-17-jdk-headless wget curl unzip debianutils libstdc++6 zlib1g ca-certificates && mkdir -p /root/android-sdk/cmdline-tools /tmp/cmdline-extracted && (wget --no-check-certificate -qO /tmp/sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip || curl -k -fL --retry 3 -o /tmp/sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip) && rm -rf /root/android-sdk/cmdline-tools/latest && unzip -qo /tmp/sdk.zip -d /tmp/cmdline-extracted && mkdir -p /root/android-sdk/cmdline-tools/latest && (if [ -d /tmp/cmdline-extracted/cmdline-tools ]; then cp -r /tmp/cmdline-extracted/cmdline-tools/* /root/android-sdk/cmdline-tools/latest/; else cp -r /tmp/cmdline-extracted/* /root/android-sdk/cmdline-tools/latest/; fi) && rm -rf /tmp/sdk.zip /tmp/cmdline-extracted && chmod +x /root/android-sdk/cmdline-tools/latest/bin/* 2>/dev/null || true && mkdir -p ~/.gradle /root/android-sdk/licenses && echo "systemProp.java.net.preferIPv4Stack=true" >> ~/.gradle/gradle.properties && echo "org.gradle.java.home=/usr/lib/jvm/java-17-openjdk-arm64" >> ~/.gradle/gradle.properties && printf "24333f8a63b6825ea9c5514f83c2829b004d1fee\\nd56f5187479451eabf01fb78af6dfcb131a6481e\\n2fa2d150aa0a1204d10e5ed57ab8369e7b50077c\\n" > /root/android-sdk/licenses/android-sdk-license && printf "84831b9409646a918e30573bab4c9c91346d8abd\\n" > /root/android-sdk/licenses/android-sdk-preview-license && printf "859f317696f67ef3d7f30a50a5560e7834b43903\\n" > /root/android-sdk/licenses/android-sdk-arm-dbt-license && printf "601085b94cd77f0b54ff86406957099ebe79c4d6\\n" > /root/android-sdk/licenses/android-googletv-license && printf "ceff83576aac4f7f37cb98fe189e9fb3c49d3b81\\n" > /root/android-sdk/licenses/android-googlexr-license && printf "33b6a2b64607f11b759f320ef9dff4ae5c47d97a\\n" > /root/android-sdk/licenses/google-gdk-license && printf "3a7848b1d7366ca5cfa0be477627644ca73f47e3\\n" > /root/android-sdk/licenses/microxr-sysimage-license && printf "e9acab5b5fbb560a72cfaecce8946896ff6aab9d\\n" > /root/android-sdk/licenses/mips-android-sysimage-license && export JAVA_HOME=\${JAVA_HOME:-\$(ls -d /usr/lib/jvm/java-17-openjdk-* /usr/lib/jvm/java-21-openjdk-* /usr/lib/jvm/java-*-openjdk-* 2>/dev/null | head -n 1)} && export PATH=\$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:\$PATH && (yes 2>/dev/null | /root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk --licenses >/dev/null 2>&1 || true) && /root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk "platform-tools" "build-tools;34.0.0" "platforms;android-34" && (${_sdkToolsArm64Command()}) && ln -sf /root/android-sdk/cmdline-tools/latest/bin/sdkmanager /usr/local/bin/sdkmanager 2>/dev/null || true && ln -sf /root/android-sdk/platform-tools/adb /usr/local/bin/adb 2>/dev/null || true && (grep -q "ANDROID_HOME" /root/.bashrc 2>/dev/null || echo "export ANDROID_HOME=/root/android-sdk" >> /root/.bashrc) && (grep -q "ANDROID_HOME" /root/.profile 2>/dev/null || echo "export ANDROID_HOME=/root/android-sdk" >> /root/.profile) && (flutter config --android-sdk /root/android-sdk 2>/dev/null || true) && (flutter config --jdk-dir \$JAVA_HOME 2>/dev/null || true) && echo "Android SDK and Java installed successfully"',
    icon: LucideIcons.smartphone,
    category: 'System',
  ),
  OptionalPackage(
    id: 'openjdk-21',
    name: 'Java OpenJDK 21 (LTS)',
    version: '21 LTS',
    description: 'Modern Java 21 JDK required for Android Gradle Plugin 8.5+, Gradle 8.10+, and newer Flutter builds',
    command: '${_aptPrefix}apt install -y openjdk-21-jdk openjdk-21-jdk-headless && update-java-alternatives -s \$(update-java-alternatives -l | grep "21" | awk \'{print \$1}\' | head -n 1) 2>/dev/null || true && java -version',
    icon: LucideIcons.coffee,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'gradle-8.13',
    name: 'Gradle 8.13 & Build Accelerator',
    version: '8.13',
    description: 'Installs Gradle 8.13 distribution and pre-caches wrapper for fast offline/online APK builds',
    command: '${_aptPrefix}apt install -y wget curl unzip openjdk-21-jdk-headless && mkdir -p /opt/gradle /root/.gradle/wrapper/dists && (wget --no-check-certificate -qO /tmp/gradle-8.13-bin.zip https://services.gradle.org/distributions/gradle-8.13-bin.zip || curl -k -fL --retry 3 -o /tmp/gradle-8.13-bin.zip https://services.gradle.org/distributions/gradle-8.13-bin.zip) && unzip -qo /tmp/gradle-8.13-bin.zip -d /opt/gradle && ln -sf /opt/gradle/gradle-8.13/bin/gradle /usr/local/bin/gradle && ln -sf /opt/gradle/gradle-8.13/bin/gradle /usr/bin/gradle && rm -f /tmp/gradle-8.13-bin.zip && gradle -v',
    icon: LucideIcons.gauge,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'apk-signing-tools',
    name: 'APK Signer, Zipalign & Bundletool',
    version: '1.17.2',
    description: 'Tools for signing release APKs, aligning binaries, and converting AAB App Bundles to universal APK',
    command: '${_aptPrefix}apt install -y apksigner zipalign aapt adb openjdk-21-jdk-headless wget curl && (wget --no-check-certificate -qO /usr/local/bin/bundletool.jar https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar || curl -k -fL --retry 3 -o /usr/local/bin/bundletool.jar https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar) && printf "#!/bin/sh\\nexec java -jar /usr/local/bin/bundletool.jar \\"\$@\\"\\n" > /usr/local/bin/bundletool && chmod +x /usr/local/bin/bundletool && printf "#!/bin/sh\\nexec java -jar /usr/lib/android-sdk/build-tools/debian/apksigner.jar \\"\$@\\"\\n" > /usr/local/bin/apksigner && chmod +x /usr/local/bin/apksigner && echo "APK Signing & Bundletool ready"',
    icon: LucideIcons.shield_check,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-fix',
    name: 'Build Environment Fix',
    version: 'v2.6 ARM64',
    description: 'Fixes AAPT2 daemon errors, repairs AAPT/zipalign binaries, cleans legacy VM flags, and applies NDK & IPv4 Gradle patches',
    command: '${_aptPrefix}apt update && apt install --reinstall -y aapt zipalign && apt install -y adb apksigner clang lld cmake ninja-build openjdk-21-jdk pkg-config libgtk-3-dev libstdc++6 zlib1g zlib1g-dev libncurses6 libtinfo6 libc++1 libc6 && chown -R root:root /root/projects 2>/dev/null || true && chmod -R 755 /root/projects 2>/dev/null || true && git config --global --add safe.directory \'*\' 2>/dev/null || true && mkdir -p ~/.gradle && sed -i \'/extra-gen-snapshot-options/d\' ~/.gradle/gradle.properties /root/.gradle/gradle.properties 2>/dev/null || true && echo "systemProp.java.net.preferIPv4Stack=true" > ~/.gradle/gradle.properties && echo "android.aapt2.daemon=false" >> ~/.gradle/gradle.properties && echo "org.gradle.daemon=false" >> ~/.gradle/gradle.properties && echo "org.gradle.parallel=false" >> ~/.gradle/gradle.properties && echo "org.gradle.workers.max=1" >> ~/.gradle/gradle.properties && echo "android.aapt2FromMaven=false" >> ~/.gradle/gradle.properties && echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> ~/.gradle/gradle.properties && ( if [ -f /usr/bin/aapt2 ] && /usr/bin/aapt2 version 2>/dev/null | grep -q "debian"; then echo "Upgrading aapt2 to modern ARM64 binary..." && mkdir -p /tmp/aapt2_download && ( curl -L -o /tmp/aapt2_download/aapt2 https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a || wget -O /tmp/aapt2_download/aapt2 https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a ) && chmod +x /tmp/aapt2_download/aapt2 && mv /tmp/aapt2_download/aapt2 /usr/bin/aapt2 && rm -rf /tmp/aapt2_download && echo "aapt2 successfully upgraded."; fi ) && rm -rf ~/.gradle/caches && ( find /root/android-sdk -name "aapt2" -exec cp /usr/bin/aapt2 {} \\; 2>/dev/null || true ) && ( find /root/.gradle -name "aapt2" -exec cp /usr/bin/aapt2 {} \\; 2>/dev/null || true ) && ( for bt in /root/android-sdk/build-tools/*; do if [ -d "\$bt" ]; then ln -sf /usr/bin/aapt "\$bt/aapt" 2>/dev/null || true; ln -sf /usr/bin/zipalign "\$bt/zipalign" 2>/dev/null || true; ln -sf /usr/bin/aapt2 "\$bt/aapt2" 2>/dev/null || true; fi; done ) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && touch /root/.quantum_build_fix_installed ~/.quantum_build_fix_installed 2>/dev/null || true && echo "Fixed global build environment, C++ dependencies, Git directories, disabled AAPT2 daemon, upgraded aapt2 binary, and cleared Gradle cache"',
    icon: LucideIcons.wrench,
    category: 'System',
  ),
  OptionalPackage(
    id: 'box64-emulator',
    name: 'Box64 (x86_64 Emulator)',
    version: '0.4.5',
    description: 'Enables running x86_64 Linux executables with full Vulkan 1.4, overlays, and OpenGL hardware acceleration on ARM64 Android',
    command: 'which box64 || (apt install -y git cmake ninja-build clang libvulkan-dev libvulkan1 && rm -rf /tmp/box64 && git clone --depth 1 https://github.com/ptitSeb/box64.git /tmp/box64 && cd /tmp/box64 && mkdir build && cd build && cmake .. -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=Release -GNinja && ninja -j4 && ninja install && rm -rf /tmp/box64 && box64 -v)',
    icon: LucideIcons.cpu,
    category: 'System',
  ),
  OptionalPackage(
    id: 'vulkan-graphics',
    name: 'Vulkan 3D & Mesa Turnip Drivers',
    version: '1.4.304',
    description: 'Hardware GPU 3D acceleration for ARM64 Android. Installs Vulkan loader, tools, Turnip Adreno drivers, and Zink (OpenGL over Vulkan)',
    command: '${_aptPrefix}apt install -y vulkan-tools libvulkan1 libvulkan-dev mesa-vulkan-drivers libgl1-mesa-dri && (if [ -f /system/lib64/libvulkan.so ]; then mkdir -p /usr/lib/aarch64-linux-gnu && ln -sf /system/lib64/libvulkan.so /usr/lib/aarch64-linux-gnu/libvulkan.so.1 2>/dev/null || true; fi) && vulkaninfo --summary 2>/dev/null || echo "Vulkan 3D graphics stack ready"',
    icon: LucideIcons.zap,
    category: 'System',
  ),
  OptionalPackage(
    id: 'build-clean',
    name: 'Clean & Repair Build',
    version: 'Utility',
    description: 'Runs flutter clean, removes gradle caches, and resets build state',
    command: 'rm -rf ~/.gradle/caches && rm -rf build && if [ -f pubspec.yaml ]; then flutter clean; echo "Project and Global caches cleaned"; else echo "Global Gradle caches cleared. (Note: Run inside project folder to clean flutter specific files)"; fi',
    icon: LucideIcons.refresh_ccw,
    category: 'System',
  ),
  // ==========================================
  // CMAKE & NATIVE BUILD LIBRARIES
  // ==========================================
  OptionalPackage(
    id: 'cmake-3.22',
    name: 'CMake 3.22.1 (ARM64 Native)',
    version: '3.22.1 LTS',
    description: 'Native ARM64 build tool with Ninja for C++ and Android NDK',
    command: _cmakeArm64Command('3.22.1', '3.22.1'),
    icon: LucideIcons.package_open,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'cmake-3.31',
    name: 'CMake 3.31.0 (ARM64 Native)',
    version: '3.31.0',
    description: 'Native ARM64 build tool for modern C++ and Android NDK',
    command: _cmakeArm64Command('3.31.0', '3.31.0'),
    icon: LucideIcons.package_open,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'mold-linker',
    name: 'Mold High-Speed Linker',
    version: '2.x ARM64',
    description: 'High-performance linker (up to 4x faster than LLD) for rapid C/C++ compilation on ARM',
    command: _moldLinkerCommand(),
    icon: LucideIcons.zap,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'rust-arm64',
    name: 'Rust & Cargo (Android ARM64)',
    version: 'Latest Stable',
    description: 'Rust compiler and Cargo with aarch64-linux-android cross-compilation targets',
    command: _rustArm64Command(),
    icon: LucideIcons.shield,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'protobuf-compiler',
    name: 'Protobuf & gRPC Compiler (protoc)',
    version: '3.21+',
    description: 'Protocol Buffers compiler and headers for gRPC and binary serialization builds',
    command: '${_aptPrefix}apt install -y protobuf-compiler libprotobuf-dev',
    icon: LucideIcons.binary,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'sqlite-dev',
    name: 'SQLite3, OpenSSL & FFI Dev Libraries',
    version: '3.45+',
    description: 'Native headers and libraries (libsqlite3-dev, libssl-dev, libffi-dev) for Drift, SQLite, and FFI builds',
    command: '${_aptPrefix}apt install -y sqlite3 libsqlite3-dev libssl-dev libffi-dev',
    icon: LucideIcons.database,
    category: 'Build Tools',
  ),

  // ==========================================
  // NDK VERSIONS (ARM64 Native)
  // ==========================================
  OptionalPackage(
    id: 'ndk-r25c',
    name: 'NDK r25c (ARM64 LTS)',
    version: '25.1.8937393',
    description: 'Android Native Development Kit with ARM64 Clang/LLVM and ndk-build (Classic LTS)',
    command: _ndkArm64Command(
      versionDir: '25.1.8937393',
      aliasName: 'r25c',
      primaryUrl: 'https://github.com/Lesorub361/quantum_ide/releases/download/v1.2.32/android-ndk-r25c-aarch64-linux-android.tar.xz',
      fallbackUrl: 'https://github.com/HomuHomu833/android-ndk-custom/releases/download/r25/android-ndk-r25c-aarch64-linux-android.tar.xz',
    ),
    icon: LucideIcons.cpu,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'ndk-r27b',
    name: 'NDK r27b (ARM64 LTS)',
    version: '27.0.12077973',
    description: 'Android Native Development Kit with ARM64 Clang/LLVM and ndk-build (Flutter Default)',
    command: _ndkArm64Command(
      versionDir: '27.0.12077973',
      aliasName: 'r27b',
      primaryUrl: 'https://github.com/Lesorub361/quantum_ide/releases/download/v1.2.32/android-ndk-r27-aarch64-linux-android.tar.xz',
      fallbackUrl: 'https://github.com/HomuHomu833/android-ndk-custom/releases/download/r27/android-ndk-r27-aarch64-linux-android.tar.xz',
    ),
    icon: LucideIcons.cpu,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'ndk-r28',
    name: 'NDK r28 (ARM64 16KB Pages)',
    version: '28.0.12433547',
    description: 'Android Native Development Kit r28 with full Android 15/16 16KB page alignment support',
    command: _ndkArm64Command(
      versionDir: '28.0.12433547',
      aliasName: 'r28',
      primaryUrl: 'https://github.com/HomuHomu833/android-ndk-custom/releases/download/r28/android-ndk-r28-aarch64-linux-android.tar.xz',
      fallbackUrl: 'https://github.com/HomuHomu833/android-ndk-custom/releases/download/r28/android-ndk-r28-aarch64-linux-gnu.tar.xz',
    ),
    icon: LucideIcons.cpu,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'ndk-r29',
    name: 'NDK r29 (ARM64 Latest)',
    version: '29.0.14206865',
    description: 'Android Native Development Kit (29.0.14206865 Bleeding Edge for ARM64)',
    command: _ndkArm64Command(
      versionDir: '29.0.14206865',
      aliasName: 'r29',
      primaryUrl: 'https://github.com/lzhiyong/termux-ndk/releases/download/android-ndk/android-ndk-r29-aarch64.tar.xz',
      fallbackUrl: 'https://github.com/HomuHomu833/android-ndk-custom/releases/download/r29/android-ndk-r29-aarch64-linux-android.tar.xz',
    ),
    icon: LucideIcons.cpu,
    category: 'Build Tools',
  ),

  // ==========================================
  // SDK BUILD TOOLS & PLATFORM TOOLS (ARM64)
  // ==========================================
  OptionalPackage(
    id: 'android-sdk-tools-arm64',
    name: 'SDK Build-Tools & ADB Suite (ARM64)',
    version: '35.0.2 Static',
    description: 'Static ARM64 aapt2, aapt, zipalign, aidl, adb, and fastboot suite for on-device builds and wireless debugging',
    command: _sdkToolsArm64Command(),
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-35.0.0',
    name: 'Build-Tools 35.0.0 (ARM64)',
    version: '35.0.0',
    description: 'Android SDK Build-Tools 35.0.0 with native ARM64 aapt2, aapt and zipalign',
    command: _sdkToolsArm64Command(),
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-34.0.0',
    name: 'Build-Tools 34.0.0 (ARM64)',
    version: '34.0.0',
    description: 'Android SDK Build-Tools 34.0.0 with native ARM64 aapt2, aapt and zipalign',
    command: _sdkToolsArm64Command(),
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-35.0.1',
    name: 'Build-Tools 35.0.1 (ARM64)',
    version: '35.0.1',
    description: 'Android SDK Build-Tools 35.0.1 with native ARM64 aapt2, aapt and zipalign',
    command: _sdkToolsArm64Command(),
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-36.0.0',
    name: 'Build-Tools 36.0.0 (ARM64)',
    version: '36.0.0',
    description: 'Android SDK Build-Tools 36.0.0 with native ARM64 aapt2, aapt and zipalign',
    command: _sdkToolsArm64Command(),
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),

  // ==========================================
  // SDK PLATFORMS
  // ==========================================
  OptionalPackage(
    id: 'platform-android-21',
    name: 'Android SDK Platform 21',
    description: 'Android 5.0 (Lollipop) API Level 21',
    command: '$_sdkPrefix "platforms;android-21"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-24',
    name: 'Android SDK Platform 24',
    description: 'Android 7.0 (Nougat) API Level 24',
    command: '$_sdkPrefix "platforms;android-24"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-26',
    name: 'Android SDK Platform 26',
    description: 'Android 8.0 (Oreo) API Level 26',
    command: '$_sdkPrefix "platforms;android-26"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-28',
    name: 'Android SDK Platform 28',
    description: 'Android 9.0 (Pie) API Level 28',
    command: '$_sdkPrefix "platforms;android-28"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-29',
    name: 'Android SDK Platform 29',
    description: 'Android 10.0 API Level 29',
    command: '$_sdkPrefix "platforms;android-29"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-30',
    name: 'Android SDK Platform 30',
    description: 'Android 11.0 API Level 30',
    command: '$_sdkPrefix "platforms;android-30"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-31',
    name: 'Android SDK Platform 31',
    description: 'Android 12.0 API Level 31',
    command: '$_sdkPrefix "platforms;android-31"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-33',
    name: 'Android SDK Platform 33',
    description: 'Android 13.0 API Level 33',
    command: '$_sdkPrefix "platforms;android-33"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-34',
    name: 'Android SDK Platform 34',
    description: 'Android 14.0 API Level 34',
    command: '$_sdkPrefix "platforms;android-34"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-35',
    name: 'Android SDK Platform 35',
    description: 'Android 15.0 API Level 35',
    command: '$_sdkPrefix "platforms;android-35"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-36',
    name: 'Android SDK Platform 36',
    description: 'Android 16.0 API Level 36 (Latest Stable)',
    command: '$_sdkPrefix "platforms;android-36"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'platform-android-37',
    name: 'Android SDK Platform 37',
    description: 'Android 17.0 API Level 37 (Preview)',
    command: '$_sdkPrefix "platforms;android-37"',
    icon: LucideIcons.layers,
    category: 'SDK Platforms',
  ),
  OptionalPackage(
    id: 'java-lsp',
    name: 'Java Language Server (JDTLS)',
    description: 'Eclipse JDT Language Server for Java code completion, errors, and analysis',
    command: _aptPrefix + r'apt install -y openjdk-21-jdk-headless wget curl unzip tar ca-certificates && mkdir -p /usr/share/jdtls && (curl -k -fL --retry 3 -o /tmp/jdtls.tar.gz https://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz || wget --no-check-certificate -qO /tmp/jdtls.tar.gz https://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz) && tar -xzf /tmp/jdtls.tar.gz -C /usr/share/jdtls && rm -f /tmp/jdtls.tar.gz && printf "#!/bin/sh\nLAUNCHER_JAR=\$(ls /usr/share/jdtls/plugins/org.eclipse.equinox.launcher_*.jar | head -n 1)\nexec java -jar \$LAUNCHER_JAR -configuration /usr/share/jdtls/config_linux -data /root/.jdtls-workspace \"\$@\"\n" > /usr/local/bin/jdtls && chmod +x /usr/local/bin/jdtls && ln -sf /usr/local/bin/jdtls /usr/bin/jdtls 2>/dev/null || true',
    icon: LucideIcons.coffee,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'kotlin-lsp',
    name: 'Kotlin Language Server',
    description: 'Kotlin Language Server for code autocompletion, diagnostics, and hover information',
    command: _aptPrefix + r'apt install -y openjdk-21-jdk-headless wget curl unzip ca-certificates && mkdir -p /usr/share/kotlin-language-server && (wget --no-check-certificate -qO /tmp/ktls.zip https://github.com/fwcd/kotlin-language-server/releases/latest/download/server.zip || curl -k -fL --retry 3 -o /tmp/ktls.zip https://github.com/fwcd/kotlin-language-server/releases/latest/download/server.zip) && unzip -qo /tmp/ktls.zip -d /usr/share/kotlin-language-server && rm -f /tmp/ktls.zip && chmod +x /usr/share/kotlin-language-server/server/bin/kotlin-language-server 2>/dev/null || true && ln -sf /usr/share/kotlin-language-server/server/bin/kotlin-language-server /usr/local/bin/kotlin-language-server 2>/dev/null || true && ln -sf /usr/local/bin/kotlin-language-server /usr/bin/kotlin-language-server 2>/dev/null || true',
    icon: LucideIcons.file_code,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'typescript-lsp',
    name: 'JavaScript & TypeScript IDE Plugin',
    description: 'Provides autocomplete, hover, diagnostics, and code outline for JavaScript and TypeScript projects.',
    command: _aptPrefix + r'apt install -y curl ca-certificates && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x || curl -fsSL https://deb.nodesource.com/setup_20.x) | bash - && apt install -y nodejs && npm install -g typescript typescript-language-server && (ln -sf /usr/local/lib/nodejs/bin/typescript-language-server /usr/local/bin/typescript-language-server 2>/dev/null || true)',
    icon: LucideIcons.code,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'html-css-lsp',
    name: 'HTML & CSS IDE Plugin',
    description: 'Provides autocomplete, tags helper, and CSS validation for HTML and CSS files.',
    command: _aptPrefix + r'apt install -y curl ca-certificates && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x || curl -fsSL https://deb.nodesource.com/setup_20.x) | bash - && apt install -y nodejs && npm install -g vscode-langservers-extracted && (for b in vscode-html-language-server vscode-css-language-server; do ln -sf /usr/local/lib/nodejs/bin/$b /usr/local/bin/$b 2>/dev/null || true; done)',
    icon: LucideIcons.globe,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'yaml-json-lsp',
    name: 'YAML & JSON IDE Plugin',
    description: 'Provides autocomplete, validation, and schema support for configuration files (YAML, JSON, Pubspec).',
    command: _aptPrefix + r'apt install -y curl ca-certificates && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x || curl -fsSL https://deb.nodesource.com/setup_20.x) | bash - && apt install -y nodejs && npm install -g yaml-language-server vscode-langservers-extracted && (for b in yaml-language-server vscode-json-language-server; do ln -sf /usr/local/lib/nodejs/bin/$b /usr/local/bin/$b 2>/dev/null || true; done)',
    icon: LucideIcons.file_text,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'markdown-lsp',
    name: 'Markdown IDE Plugin (Marksman)',
    description: 'Provides smart autocomplete, link tracking, wiki-link support, and formatting for Markdown documents.',
    command: _aptPrefix + r'apt install -y curl wget ca-certificates && ARCH=$(uname -m) && if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then M_ARCH="arm64"; else M_ARCH="x64"; fi && ( wget --no-check-certificate -qO /usr/local/bin/marksman-bin "https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-${M_ARCH}" || curl -k -fL --retry 3 -o /usr/local/bin/marksman-bin "https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-${M_ARCH}" ) && chmod +x /usr/local/bin/marksman-bin && printf "#!/bin/sh\nexport DOTNET_GCHeapHardLimit=0x10000000\nexec /usr/local/bin/marksman-bin \"\$@\"\n" > /usr/local/bin/marksman && chmod +x /usr/local/bin/marksman && ln -sf /usr/local/bin/marksman /usr/bin/marksman 2>/dev/null || true',
    icon: LucideIcons.file_text,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'vue-lsp',
    name: 'Vue.js IDE Plugin',
    description: 'Provides Vue 3 autocomplete, formatting, diagnostics, and template checking (Volar language server).',
    command: _aptPrefix + r'apt update && apt install -y curl && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x || curl -fsSL https://deb.nodesource.com/setup_20.x) | bash - && apt install -y nodejs && npm install -g @vue/language-server && (ln -sf /usr/local/lib/nodejs/bin/vue-language-server /usr/local/bin/vue-language-server 2>/dev/null || true)',
    icon: LucideIcons.layout_template,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'php-lsp',
    name: 'PHP IDE Plugin',
    description: 'Provides PHP autocomplete, signature help, code diagnostics, and formatting (Intelephense).',
    command: _aptPrefix + r'apt update && apt install -y curl && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x || curl -fsSL https://deb.nodesource.com/setup_20.x) | bash - && apt install -y nodejs && npm install -g intelephense && (ln -sf /usr/local/lib/nodejs/bin/intelephense /usr/local/bin/intelephense 2>/dev/null || true)',
    icon: LucideIcons.server,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'python-lsp',
    name: 'Python IDE Plugin',
    description: 'Provides type checking, auto-imports, autocompletions, and diagnostics for Python projects (Pyright).',
    command: _aptPrefix + r'apt update && apt install -y curl && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x || curl -fsSL https://deb.nodesource.com/setup_20.x) | bash - && apt install -y nodejs && npm install -g pyright && (ln -sf /usr/local/lib/nodejs/bin/pyright /usr/local/bin/pyright 2>/dev/null || true)',
    icon: LucideIcons.terminal,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'clangd-lsp',
    name: 'C/C++ Language Server (Clangd)',
    description: 'Provides fast autocompletion, compile errors, goto definition, and refactoring for C and C++.',
    command: '${_aptPrefix}apt update && apt install -y clangd clang-tools',
    icon: LucideIcons.cpu,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'rust-lsp',
    name: 'Rust Analyzer & Cargo',
    description: 'Official Rust language server for code intelligence, completion, and linting.',
    command: '${_aptPrefix}apt update && (apt install -y rustc cargo rust-analyzer 2>/dev/null || (curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && (grep -q ".cargo/bin" /root/.bashrc 2>/dev/null || echo "export PATH=\\\$PATH:/root/.cargo/bin" >> /root/.bashrc)))',
    icon: LucideIcons.cog,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'go-lsp',
    name: 'Go & Gopls Language Server',
    description: 'Google Go compiler and official gopls language server for full Go language support.',
    command: '${_aptPrefix}apt update && apt install -y golang-go gopls 2>/dev/null || (apt install -y golang-go && go install golang.org/x/tools/gopls@latest && cp ~/go/bin/gopls /usr/local/bin/ 2>/dev/null || true)',
    icon: LucideIcons.send,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'ripgrep',
    name: 'Ripgrep (rg)',
    description: 'Ultra-fast recursive search utility for instant workspace symbol and text search.',
    command: '${_aptPrefix}apt update && apt install -y ripgrep',
    icon: LucideIcons.search,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'gh-cli',
    name: 'GitHub CLI (gh)',
    description: 'Official command-line tool for GitHub issues, pull requests, and repository cloning.',
    command: '${_aptPrefix}apt update && (apt install -y gh 2>/dev/null || (curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && apt update && apt install -y gh))',
    icon: LucideIcons.git_pull_request,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'uv',
    name: 'uv (Fast Python Toolchain)',
    description: 'Extremely fast Python package installer and resolver written in Rust.',
    command: '${_aptPrefix}apt install -y curl ca-certificates && (curl -LsSf https://astral.sh/uv/install.sh | sh) && (ln -sf /root/.cargo/bin/uv /usr/local/bin/uv 2>/dev/null || ln -sf /root/.local/bin/uv /usr/local/bin/uv 2>/dev/null || true)',
    icon: LucideIcons.zap,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'bun',
    name: 'Bun (Fast JS/TS Runtime)',
    description: 'Incredibly fast all-in-one JavaScript and TypeScript runtime, bundler, and package manager.',
    command: '${_aptPrefix}apt install -y curl unzip ca-certificates && (curl -fsSL https://bun.sh/install | bash) && (ln -sf /root/.bun/bin/bun /usr/local/bin/bun 2>/dev/null || true)',
    icon: LucideIcons.flame,
    category: 'Web',
  ),
  OptionalPackage(
    id: 'pnpm',
    name: 'pnpm (Fast Package Manager)',
    description: 'Fast, disk space efficient package manager for modern web projects.',
    command: 'if which npm >/dev/null 2>&1; then (npm install -g pnpm@9 --ignore-scripts || npm install -g pnpm --ignore-scripts); else ${_aptPrefix}apt install -y curl && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs) && npm install -g pnpm@9 --ignore-scripts; fi && (ln -sf /usr/local/lib/nodejs/bin/pnpm /usr/local/bin/pnpm 2>/dev/null || true)',
    icon: LucideIcons.package,
    category: 'Web',
  ),
  OptionalPackage(
    id: 'desktop-build-tools',
    name: 'Linux Desktop (PC) Build Tools',
    description: 'Essential C++ libraries and tools (clang, cmake, ninja, pkg-config, GTK 3, libsecret, epoxy) required to compile Flutter Desktop/PC apps and plugins.',
    command: '${_aptPrefix}apt update && apt install -y clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev liblzma-dev libepoxy-dev libjsoncpp-dev && (flutter config --enable-linux-desktop 2>/dev/null || true) && echo "Linux Desktop build tools installed and desktop enabled in Flutter"',
    icon: LucideIcons.monitor,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'flutter-distributor',
    name: 'Flutter Distributor',
    description: 'All-in-one packaging and publishing tool for Flutter apps across Android, Linux desktop, and Web.',
    command: 'if which dart >/dev/null 2>&1; then dart pub global activate flutter_distributor && (ln -sf /root/.pub-cache/bin/flutter_distributor /usr/local/bin/flutter_distributor 2>/dev/null || true); else echo "Flutter/Dart SDK required first"; fi',
    icon: LucideIcons.share_2,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'quantum-ide-update',
    name: 'Quantum IDE: Автообновление & Лекарь SDK',
    version: '1.2.78',
    description: 'Пакет в 1 клик: скачивает свежий релиз Quantum IDE с GitHub в Загрузки, автоматически лечит ограничения версий Dart SDK в проектах и обновляет среду разработки.',
    command: 'curl -fsSL https://raw.githubusercontent.com/Lesorub361/quantum_ide/main/scripts/quantum-update.sh | bash',
    icon: LucideIcons.sparkles,
    category: 'System',
  ),
];
