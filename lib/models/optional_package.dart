import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class OptionalPackage {
  final String id;
  final String name;
  final String description;
  final String command;
  final IconData icon;
  final String category;
  bool isInstalled;
  bool isInstalling;

  OptionalPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.command,
    required this.icon,
    this.category = 'Tools',
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
    'export JAVA_HOME=\${JAVA_HOME:-\$(ls -d /usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | head -n 1)} && '
    'export PATH=\$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:\$PATH && '
    '(yes 2>/dev/null | /root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk --licenses >/dev/null 2>&1 || true) && '
    '/root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk';

final defaultPackages = [
  OptionalPackage(
    id: 'python',
    name: 'Python 3',
    description: 'General-purpose programming language',
    command: '${_aptPrefix}apt install -y python3 python3-pip python-is-python3',
    icon: LucideIcons.terminal,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'nodejs',
    name: 'Node.js 20',
    description: 'JavaScript runtime (v20.x) for modern tools and CLI',
    command: 'if which node >/dev/null 2>&1 && which npm >/dev/null 2>&1; then echo "Node.js already installed: \$(node -v)"; else ${_aptPrefix}apt install -y curl ca-certificates && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs; fi',
    icon: LucideIcons.zap,
    category: 'Web',
  ),
  OptionalPackage(
    id: 'git',
    name: 'Git',
    description: 'Distributed version control system',
    command: '${_aptPrefix}apt install -y git ca-certificates',
    icon: LucideIcons.git_branch,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'flutter',
    name: 'Flutter & Dart SDK (Language Support)',
    description: 'Google\'s UI toolkit for building natively compiled Dart and Flutter applications with full IDE language server support.',
    command: '${_aptPrefix}apt install -y git curl unzip xz-utils libglu1-mesa debianutils ca-certificates && git config --global --add safe.directory \'*\' 2>/dev/null || true && if [ -d /root/flutter/.git ]; then cd /root/flutter && git pull && /root/flutter/bin/flutter precache; else rm -rf /root/flutter && git clone --depth 1 https://github.com/flutter/flutter.git -b stable /root/flutter && /root/flutter/bin/flutter precache; fi && (grep -q "/root/flutter/bin" /root/.bashrc 2>/dev/null || echo "export PATH=\\\$PATH:/root/flutter/bin" >> /root/.bashrc)',
    icon: LucideIcons.code,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'antigravity-cli',
    name: 'Antigravity CLI (agy)',
    description: 'Official CLI tool for Google Antigravity AI models and autonomous agent orchestration',
    command: '${_aptPrefix}apt install -y curl tar gzip && ARCH=\$(uname -m) && if [ "\$ARCH" = "aarch64" ] || [ "\$ARCH" = "arm64" ]; then URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-arm/cli_linux_arm64.tar.gz"; else URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-x64/cli_linux_x64.tar.gz"; fi && mkdir -p /tmp/agy_dl && curl -fL --retry 3 "\$URL" | tar -xz -C /tmp/agy_dl && mkdir -p /usr/local/bin && mv /tmp/agy_dl/antigravity /usr/local/bin/agy && ln -sf /usr/local/bin/agy /usr/local/bin/antigravity && chmod +x /usr/local/bin/agy && rm -rf /tmp/agy_dl && echo "Antigravity CLI installed successfully"',
    icon: LucideIcons.sparkles,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'claude-code',
    name: 'Claude Code CLI (claude)',
    description: 'Anthropic\'s autonomous coding assistant CLI with full terminal execution and file editing',
    command: 'if which npm >/dev/null 2>&1; then (npm install -g @anthropic-ai/claude-code || sudo npm install -g @anthropic-ai/claude-code); else ${_aptPrefix}apt install -y curl && (curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs) && (npm install -g @anthropic-ai/claude-code || sudo npm install -g @anthropic-ai/claude-code); fi',
    icon: LucideIcons.bot,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'deepseek-harness',
    name: 'DeepSeek Harness CLI (dsh)',
    description: 'DeepSeek autonomous agent runner for complex refactoring, reasoning, and test generation',
    command: '${_aptPrefix}apt install -y curl && (which node >/dev/null 2>&1 || (curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs)) && npm install -g @deepseek-ai/dsh && (if [ ! -f /usr/local/bin/dsh ]; then printf "#!/bin/sh\\nexec node /usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh/lib/bin.js \\"\$@\\"\\n" > /usr/local/bin/dsh && chmod +x /usr/local/bin/dsh; fi) && echo "DeepSeek Harness installed successfully"',
    icon: LucideIcons.brain_circuit,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'ollama-cli',
    name: 'Ollama CLI',
    description: 'Run large language models locally (Llama 3, Mistral, Qwen, etc.)',
    command: '${_aptPrefix}apt install -y curl && curl -fsSL https://ollama.com/install.sh | sh',
    icon: LucideIcons.brain,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'kilocode-cli',
    name: 'KiloCode CLI',
    description: 'Command-line interface for KiloCode development',
    command: 'if which npm >/dev/null 2>&1; then (npm install -g @kilocode/cli || sudo npm install -g @kilocode/cli); else ${_aptPrefix}apt install -y curl && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && (npm install -g @kilocode/cli || sudo npm install -g @kilocode/cli); fi',
    icon: LucideIcons.code,
    category: 'Tools',
  ),
  OptionalPackage(
    id: 'opencode-ai',
    name: 'OpenCode AI',
    description: 'AI-powered coding assistant and tools',
    command: 'if which npm >/dev/null 2>&1; then (npm i -g opencode-ai || sudo npm i -g opencode-ai) && (curl -4 -fsSL https://opencode.ai/install | bash || true); else ${_aptPrefix}apt install -y curl && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && (npm i -g opencode-ai || sudo npm i -g opencode-ai) && (curl -4 -fsSL https://opencode.ai/install | bash || true); fi',
    icon: LucideIcons.brain_circuit,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'local-ai-qwen',
    name: 'Local Llama Server',
    description: 'Local engine to run offline AI models (llama-server and llama-cli).',
    command: '${_aptPrefix}apt install -y curl wget tar ca-certificates && mkdir -p /tmp/llama_download && cd /tmp/llama_download && (wget --no-check-certificate -q https://github.com/ggml-org/llama.cpp/releases/download/b4200/llama-b4200-bin-ubuntu-arm64.tar.gz || curl -k -fL --retry 3 -o llama-b4200-bin-ubuntu-arm64.tar.gz https://github.com/ggml-org/llama.cpp/releases/download/b4200/llama-b4200-bin-ubuntu-arm64.tar.gz) && tar -xzf llama-b4200-bin-ubuntu-arm64.tar.gz && cp bin/llama-server /usr/bin/llama-server && cp bin/llama-cli /usr/bin/llama-cli && rm -rf /tmp/llama_download && echo "Llama Server installed successfully"',
    icon: LucideIcons.brain,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'build-essential',
    name: 'C++ Build Tools',
    description: 'GCC, G++, and other essential tools for C/C++ development',
    command: '${_aptPrefix}apt update && apt install -y build-essential',
    icon: LucideIcons.box,
    category: 'System',
  ),
  OptionalPackage(
    id: 'android-sdk',
    name: 'Android SDK & Java',
    description: 'Essential for Android builds (Java 17, cmdline-tools, platform-tools)',
    command: '${_aptPrefix}apt install -y openjdk-17-jdk-headless wget curl unzip debianutils libstdc++6 zlib1g ca-certificates && mkdir -p /root/android-sdk/cmdline-tools /tmp/cmdline-extracted && (wget --no-check-certificate -qO /tmp/sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip || curl -k -fL --retry 3 -o /tmp/sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip) && rm -rf /root/android-sdk/cmdline-tools/latest && unzip -qo /tmp/sdk.zip -d /tmp/cmdline-extracted && mkdir -p /root/android-sdk/cmdline-tools/latest && (if [ -d /tmp/cmdline-extracted/cmdline-tools ]; then cp -r /tmp/cmdline-extracted/cmdline-tools/* /root/android-sdk/cmdline-tools/latest/; else cp -r /tmp/cmdline-extracted/* /root/android-sdk/cmdline-tools/latest/; fi) && rm -rf /tmp/sdk.zip /tmp/cmdline-extracted && chmod +x /root/android-sdk/cmdline-tools/latest/bin/* 2>/dev/null || true && mkdir -p ~/.gradle && echo "systemProp.java.net.preferIPv4Stack=true" >> ~/.gradle/gradle.properties && export JAVA_HOME=\${JAVA_HOME:-\$(ls -d /usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | head -n 1)} && export PATH=\$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:\$PATH && (yes 2>/dev/null | /root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk --licenses >/dev/null 2>&1 || true) && /root/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/root/android-sdk "platform-tools" "build-tools;34.0.0" "platforms;android-34" && (flutter config --android-sdk /root/android-sdk 2>/dev/null || true) && echo "Android SDK and Java installed successfully"',
    icon: LucideIcons.settings_2,
    category: 'System',
  ),
  OptionalPackage(
    id: 'build-fix',
    name: 'Build Environment Fix',
    description: 'Fixes AAPT2 daemon errors, project permissions, and forces IPv4 Gradle settings (global)',
    command: '${_aptPrefix}apt update && apt install -y adb aapt zipalign apksigner clang lld cmake ninja-build openjdk-21-jdk pkg-config libgtk-3-dev libstdc++6 zlib1g zlib1g-dev libncurses6 libtinfo6 libc++1 libc6 && chown -R root:root /root/projects && chmod -R 755 /root/projects && git config --global --add safe.directory \'*\' && mkdir -p ~/.gradle && echo "systemProp.java.net.preferIPv4Stack=true" > ~/.gradle/gradle.properties && echo "android.aapt2.daemon=false" >> ~/.gradle/gradle.properties && echo "org.gradle.daemon=false" >> ~/.gradle/gradle.properties && echo "org.gradle.parallel=false" >> ~/.gradle/gradle.properties && echo "org.gradle.workers.max=1" >> ~/.gradle/gradle.properties && echo "android.aapt2FromMaven=false" >> ~/.gradle/gradle.properties && echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> ~/.gradle/gradle.properties && ( if [ -f /usr/bin/aapt2 ] && /usr/bin/aapt2 version 2>/dev/null | grep -q "debian"; then echo "Upgrading aapt2 to modern ARM64 binary..." && mkdir -p /tmp/aapt2_download && ( curl -L -o /tmp/aapt2_download/aapt2 https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a || wget -O /tmp/aapt2_download/aapt2 https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a ) && chmod +x /tmp/aapt2_download/aapt2 && mv /tmp/aapt2_download/aapt2 /usr/bin/aapt2 && rm -rf /tmp/aapt2_download && echo "aapt2 successfully upgraded."; fi ) && rm -rf ~/.gradle/caches && ( find /root/android-sdk -name "aapt2" -exec cp /usr/bin/aapt2 {} \\; 2>/dev/null || true ) && ( find /root/.gradle -name "aapt2" -exec cp /usr/bin/aapt2 {} \\; 2>/dev/null || true ) && echo "Fixed global build environment, C++ dependencies, Git directories, disabled AAPT2 daemon, upgraded aapt2 binary, and cleared Gradle cache"',
    icon: LucideIcons.wrench,
    category: 'System',
  ),
  OptionalPackage(
    id: 'build-clean',
    name: 'Clean & Repair Build',
    description: 'Runs flutter clean, removes gradle caches, and resets build state',
    command: 'rm -rf ~/.gradle/caches && rm -rf build && if [ -f pubspec.yaml ]; then flutter clean; echo "Project and Global caches cleaned"; else echo "Global Gradle caches cleared. (Note: Run inside project folder to clean flutter specific files)"; fi',
    icon: LucideIcons.refresh_ccw,
    category: 'System',
  ),
  // ==========================================
  // CMAKE VERSIONS
  // ==========================================
  OptionalPackage(
    id: 'cmake-3.22',
    name: 'CMake 3.22.1',
    description: 'Build tool for C++ (Recommended LTS)',
    command: '$_sdkPrefix "cmake;3.22.1"',
    icon: LucideIcons.box,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'cmake-3.31',
    name: 'CMake 3.31.0',
    description: 'Build tool for C++ (Latest)',
    command: '$_sdkPrefix "cmake;3.31.0"',
    icon: LucideIcons.box,
    category: 'Build Tools',
  ),

  // ==========================================
  // NDK VERSIONS
  // ==========================================
  OptionalPackage(
    id: 'ndk-r25c',
    name: 'NDK r25c (LTS)',
    description: 'Android Native Development Kit (25.1.8937393 - Recommended)',
    command: '$_sdkPrefix "ndk;25.1.8937393"',
    icon: LucideIcons.cpu,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'ndk-r27b',
    name: 'NDK r27b (LTS)',
    description: 'Android Native Development Kit (27.0.12077973 - Modern)',
    command: '$_sdkPrefix "ndk;27.0.12077973"',
    icon: LucideIcons.cpu,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'ndk-r29',
    name: 'NDK r29 (Latest)',
    description: 'Android Native Development Kit (29.0.14206865)',
    command: '$_sdkPrefix "ndk;29.0.14206865"',
    icon: LucideIcons.cpu,
    category: 'Build Tools',
  ),

  // ==========================================
  // SDK BUILD TOOLS
  // ==========================================
  OptionalPackage(
    id: 'build-tools-28.0.3',
    name: 'Build-Tools 28.0.3',
    description: 'Android SDK Build-Tools 28.0.3 (Android 9)',
    command: '$_sdkPrefix "build-tools;28.0.3"',
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-29.0.3',
    name: 'Build-Tools 29.0.3',
    description: 'Android SDK Build-Tools 29.0.3 (Android 10)',
    command: '$_sdkPrefix "build-tools;29.0.3"',
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-30.0.3',
    name: 'Build-Tools 30.0.3',
    description: 'Android SDK Build-Tools 30.0.3 (Android 11)',
    command: '$_sdkPrefix "build-tools;30.0.3"',
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-33.0.2',
    name: 'Build-Tools 33.0.2',
    description: 'Android SDK Build-Tools 33.0.2 (Android 13)',
    command: '$_sdkPrefix "build-tools;33.0.2"',
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-34.0.0',
    name: 'Build-Tools 34.0.0',
    description: 'Android SDK Build-Tools 34.0.0 (Android 14)',
    command: '$_sdkPrefix "build-tools;34.0.0"',
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-35.0.0',
    name: 'Build-Tools 35.0.0',
    description: 'Android SDK Build-Tools 35.0.0 (Android 15)',
    command: '$_sdkPrefix "build-tools;35.0.0"',
    icon: LucideIcons.wrench,
    category: 'Build Tools',
  ),
  OptionalPackage(
    id: 'build-tools-36.0.0',
    name: 'Build-Tools 36.0.0',
    description: 'Android SDK Build-Tools 36.0.0 (Android 16)',
    command: '$_sdkPrefix "build-tools;36.0.0"',
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
    command: _aptPrefix + r'apt install -y openjdk-21-jdk-headless wget curl unzip tar ca-certificates && mkdir -p /usr/share/jdtls && (wget --no-check-certificate -qO /tmp/jdtls.tar.gz https://download.eclipse.org/jdtls/milestones/1.31.0/jdt-language-server-1.31.0-202401111522.tar.gz || curl -k -fL --retry 3 -o /tmp/jdtls.tar.gz https://download.eclipse.org/jdtls/milestones/1.31.0/jdt-language-server-1.31.0-202401111522.tar.gz) && tar -xzf /tmp/jdtls.tar.gz -C /usr/share/jdtls && rm -f /tmp/jdtls.tar.gz && echo "#!/bin/sh\nLAUNCHER_JAR=\$(ls /usr/share/jdtls/plugins/org.eclipse.equinox.launcher_*.jar | head -n 1)\njava -Declipse.application=org.eclipse.jdt.ls.core.id1 -Dosgi.bundles.defaultStartLevel=4 -Declipse.product=org.eclipse.jdt.ls.core.product -Dlog.level=ALL -noverify -Xmx1G -jar \"$LAUNCHER_JAR\" -configuration /usr/share/jdtls/config_linux -data /root/.jdtls-workspace --add-modules=ALL-SYSTEM --add-opens java.base/java.util=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED \"$@\"" > /usr/bin/jdtls && chmod +x /usr/bin/jdtls',
    icon: LucideIcons.binary,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'kotlin-lsp',
    name: 'Kotlin Language Server',
    description: 'Kotlin Language Server for code autocompletion, diagnostics, and hover information',
    command: _aptPrefix + r'apt install -y openjdk-21-jdk-headless wget curl unzip ca-certificates && mkdir -p /usr/share/kotlin-language-server && (wget --no-check-certificate -qO /tmp/ktls.zip https://github.com/fwcd/kotlin-language-server/releases/download/1.3.1/server.zip || curl -k -fL --retry 3 -o /tmp/ktls.zip https://github.com/fwcd/kotlin-language-server/releases/download/1.3.1/server.zip) && unzip -q /tmp/ktls.zip -d /usr/share && mv /usr/share/server/* /usr/share/kotlin-language-server/ && rm -rf /usr/share/server && echo "#!/bin/sh\njava -jar /usr/share/kotlin-language-server/lib/kotlin-language-server-all.jar \"$@\"" > /usr/bin/kotlin-language-server && chmod +x /usr/bin/kotlin-language-server && rm -f /tmp/ktls.zip',
    icon: LucideIcons.binary,
    category: 'AI Tools',
  ),
  OptionalPackage(
    id: 'typescript-lsp',
    name: 'JavaScript & TypeScript IDE Plugin',
    description: 'Provides autocomplete, hover, diagnostics, and code outline for JavaScript and TypeScript projects.',
    command: _aptPrefix + r'apt install -y curl ca-certificates && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && npm install -g typescript typescript-language-server',
    icon: LucideIcons.code,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'html-css-lsp',
    name: 'HTML & CSS IDE Plugin',
    description: 'Provides autocomplete, tags helper, and CSS validation for HTML and CSS files.',
    command: _aptPrefix + r'apt install -y curl ca-certificates && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && npm install -g vscode-langservers-extracted',
    icon: LucideIcons.file_code,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'yaml-json-lsp',
    name: 'YAML & JSON IDE Plugin',
    description: 'Provides autocomplete, validation, and schema support for configuration files (YAML, JSON, Pubspec).',
    command: _aptPrefix + r'apt install -y curl ca-certificates && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && npm install -g yaml-language-server vscode-langservers-extracted',
    icon: LucideIcons.settings,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'markdown-lsp',
    name: 'Markdown IDE Plugin (Marksman)',
    description: 'Provides smart autocomplete, link tracking, wiki-link support, and formatting for Markdown documents.',
    command: _aptPrefix + r'apt install -y curl wget ca-certificates && ( wget --no-check-certificate -qO /usr/bin/marksman https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-arm64 || curl -k -fL --retry 3 -o /usr/bin/marksman https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-arm64 || wget --no-check-certificate -qO /usr/bin/marksman https://github.com/artempyanykh/marksman/releases/download/v2023-12-09/marksman-linux-arm64 ) && chmod +x /usr/bin/marksman',
    icon: LucideIcons.file_text,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'vue-lsp',
    name: 'Vue.js IDE Plugin',
    description: 'Provides Vue 3 autocomplete, formatting, diagnostics, and template checking (Volar language server).',
    command: _aptPrefix + r'apt update && apt install -y curl && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && npm install -g @vue/language-server',
    icon: LucideIcons.code,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'php-lsp',
    name: 'PHP IDE Plugin',
    description: 'Provides PHP autocomplete, signature help, code diagnostics, and formatting (Intelephense).',
    command: _aptPrefix + r'apt update && apt install -y curl && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && npm install -g intelephense',
    icon: LucideIcons.code,
    category: 'Languages',
  ),
  OptionalPackage(
    id: 'python-lsp',
    name: 'Python IDE Plugin',
    description: 'Provides type checking, auto-imports, autocompletions, and diagnostics for Python projects (Pyright).',
    command: _aptPrefix + r'apt update && apt install -y curl && curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && npm install -g pyright',
    icon: LucideIcons.code,
    category: 'Languages',
  ),
];
