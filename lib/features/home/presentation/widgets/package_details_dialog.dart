import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/models/optional_package.dart';
import 'package:quantum_ide/features/home/presentation/widgets/package_install_dialog.dart';

class PackageDetailsDialog extends ConsumerWidget {
  final OptionalPackage package;

  const PackageDetailsDialog({
    super.key,
    required this.package,
  });

  static Future<void> show(BuildContext context, OptionalPackage package) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PackageDetailsDialog(package: package),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'AI Tools':
        return const Color(0xFFA855F7);
      case 'Languages':
        return const Color(0xFF10B981);
      case 'Web':
        return const Color(0xFF38BDF8);
      case 'Build Tools':
        return const Color(0xFFF59E0B);
      case 'SDK Platforms':
        return const Color(0xFFEC4899);
      case 'System':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF06B6D4);
    }
  }

  List<String> _getBinariesForPackage(OptionalPackage pkg) {
    switch (pkg.id) {
      case 'python':
        return ['python3', 'python', 'pip3', 'pip', 'venv'];
      case 'nodejs':
        return ['node', 'npm', 'npx'];
      case 'git':
        return ['git'];
      case 'git-lfs':
        return ['git-lfs'];
      case 'flutter':
        return ['flutter', 'dart'];
      case 'antigravity-cli':
        return ['agy', 'antigravity'];
      case 'claude-code':
        return ['claude'];
      case 'deepseek-harness':
        return ['dsh'];
      case 'ollama-cli':
        return ['ollama'];
      case 'kilocode-cli':
        return ['kilocode'];
      case 'opencode-ai':
        return ['opencode', 'opencode-ai'];
      case 'local-ai-qwen':
        return ['llama-server', 'llama-cli'];
      case 'build-essential':
        return ['gcc', 'g++', 'make', 'clang'];
      case 'android-sdk':
        return ['sdkmanager', 'adb', 'platforms', 'cmdline-tools'];
      case 'openjdk-21':
        return ['java (v21)', 'javac', 'jar'];
      case 'gradle-8.13':
        return ['gradle'];
      case 'apk-signing-tools':
        return ['apksigner', 'zipalign', 'bundletool', 'aapt'];
      case 'cmake-3.22':
      case 'cmake-3.31':
        return ['cmake', 'ctest'];
      case 'protobuf-compiler':
        return ['protoc', 'libprotobuf'];
      case 'sqlite-dev':
        return ['sqlite3', 'libsqlite3.so', 'libssl.so'];
      case 'java-lsp':
        return ['jdtls'];
      case 'kotlin-lsp':
        return ['kotlin-language-server'];
      case 'typescript-lsp':
        return ['typescript-language-server', 'tsserver'];
      case 'html-css-lsp':
        return ['vscode-html-language-server', 'vscode-css-language-server'];
      case 'yaml-json-lsp':
        return ['yaml-language-server', 'vscode-json-language-server'];
      case 'markdown-lsp':
        return ['marksman'];
      case 'vue-lsp':
        return ['vue-language-server'];
      case 'php-lsp':
        return ['intelephense'];
      case 'python-lsp':
        return ['pyright', 'pyright-langserver'];
      case 'clangd-lsp':
        return ['clangd'];
      case 'rust-lsp':
        return ['rustc', 'cargo', 'rust-analyzer'];
      case 'go-lsp':
        return ['go', 'gopls'];
      case 'ripgrep':
        return ['rg'];
      case 'gh-cli':
        return ['gh'];
      case 'uv':
        return ['uv', 'uvx'];
      case 'bun':
        return ['bun', 'bunx'];
      case 'pnpm':
        return ['pnpm', 'pnpx'];
      case 'desktop-build-tools':
        return ['clang', 'cmake', 'ninja'];
      case 'flutter-distributor':
        return ['flutter_distributor'];
      default:
        if (pkg.id.startsWith('ndk-')) {
          return ['clang', 'clang++', 'ndk-build', 'toolchains'];
        }
        if (pkg.id.startsWith('build-tools-')) {
          return ['aapt2', 'd8', 'apksigner', 'zipalign'];
        }
        if (pkg.id.startsWith('platform-')) {
          return ['android.jar', 'framework-res.apk'];
        }
        return [pkg.id];
    }
  }

  String _getInstallPath(OptionalPackage pkg) {
    if (pkg.id.startsWith('ndk-')) {
      final ver = pkg.id.replaceFirst('ndk-', '');
      return '/root/android-sdk/ndk/$ver';
    }
    if (pkg.id.startsWith('build-tools-')) {
      final ver = pkg.id.replaceFirst('build-tools-', '');
      return '/root/android-sdk/build-tools/$ver';
    }
    if (pkg.id.startsWith('platform-')) {
      final ver = pkg.id.replaceFirst('platform-', '');
      return '/root/android-sdk/platforms/$ver';
    }
    switch (pkg.id) {
      case 'android-sdk':
        return '/root/android-sdk (cmdline-tools, platform-tools)';
      case 'flutter':
        return '/root/flutter & /usr/local/bin';
      case 'openjdk-21':
        return '/usr/lib/jvm/java-21-openjdk-arm64';
      case 'gradle-8.13':
        return '/opt/gradle/gradle-8.13/bin/gradle';
      case 'local-ai-qwen':
        return '/opt/llama.cpp & /usr/local/bin';
      case 'java-lsp':
        return '/usr/share/jdtls & /usr/local/bin/jdtls';
      case 'kotlin-lsp':
        return '/usr/share/kotlin-language-server & /usr/local/bin';
      case 'uv':
        return '/root/.local/bin/uv & /usr/local/bin/uv';
      case 'bun':
        return '/root/.bun/bin/bun & /usr/local/bin/bun';
      case 'flutter-distributor':
        return '/root/.pub-cache/bin/flutter_distributor';
      default:
        return '/usr/local/bin & /usr/bin';
    }
  }

  String _getDetailedDescription(OptionalPackage pkg) {
    switch (pkg.id) {
      case 'python':
        return 'Полноценная среда Python 3 с менеджером пакетов pip и поддержкой изолированных виртуальных окружений venv. Необходима для AI-скриптов, ML-моделей и утилит.';
      case 'nodejs':
        return 'Современная среда выполнения JavaScript/TypeScript Node.js (LTS) и пакетный менеджер npm. Требуется для работы веб-инструментов, компиляторов и CLI-помощников.';
      case 'git':
        return 'Распределенная система контроля версий Git. Позволяет клонировать репозитории, переключать ветки, фиксировать коммиты и работать с GitHub/GitLab.';
      case 'git-lfs':
        return 'Расширение Git для работы с большими файлами (веса AI-моделей, медиа-ресурсы, скомпилированные APK/AAB и архивы).';
      case 'flutter':
        return 'Официальный Flutter & Dart SDK для сборки мобильных, настольных и веб-приложений. Включает компилятор Dart, devtools и поддержку автодополнения кода.';
      case 'antigravity-cli':
        return 'Интеллектуальный агент Antigravity CLI (agy) для автономной генерации кода, анализа проекта и выполнения команд.';
      case 'claude-code':
        return 'Официальный терминальный AI-ассистент Claude Code от Anthropic. Позволяет редактировать проект и решать задачи через естественные команды.';
      case 'deepseek-harness':
        return 'Высокопроизводительный консольный интерфейс к моделям DeepSeek (dsh) для кодогенерации и рефакторинга.';
      case 'ollama-cli':
        return 'Утилита для локального запуска открытых LLM (Llama, DeepSeek, Qwen, Mistral) без обращения к сторонним серверам.';
      case 'kilocode-cli':
        return 'Инструмент командной строки KiloCode для интеграции с AI-сервисами и быстрого прототипирования.';
      case 'opencode-ai':
        return 'Открытый AI-помощник с открытым исходным кодом для автоматизации написания кода и тестов.';
      case 'local-ai-qwen':
        return 'Локальный высокопроизводительный сервер Llama.cpp на C++ для инференса квантованных GGUF-моделей прямо на устройстве.';
      case 'build-essential':
        return 'Набор нативных компиляторов GNU C/C++ (gcc, g++, make), системных заголовочных файлов и утилит сборки нативного кода.';
      case 'android-sdk':
        return 'Базовый Android SDK: platform-tools (adb), cmdline-tools (sdkmanager), системные образы и Java 17 для сборки Android-приложений.';
      case 'openjdk-21':
        return 'Современная виртуальная машина Java 21 Long-Term Support (LTS). Рекомендуется для новейших плагинов Gradle, языковых серверов и сборщиков.';
      case 'gradle-8.13':
        return 'Автономная система сборки Gradle 8.13. Обеспечивает ускоренную параллельную сборку Android-проектов и кеширование артефактов.';
      case 'apk-signing-tools':
        return 'Набор утилит для финальной сборки Android: apksigner (подпись APK ключами), zipalign (выравнивание 4-byte для скорости загрузки) и bundletool (генерация APK из .aab).';
      case 'protobuf-compiler':
        return 'Компилятор Protobuf (protoc) и gRPC для генерации Dart/C++/Java/Go классов из .proto схем.';
      case 'sqlite-dev':
        return 'Библиотеки и заголовки SQLite3, OpenSSL и FFI для работы локальных реляционных баз данных и криптографических плагинов Flutter.';
      case 'java-lsp':
        return 'Языковой сервер Eclipse JDTLS для Java: подсветка синтаксиса, автодополнение, навигация по классам и рефакторинг в редакторе.';
      case 'kotlin-lsp':
        return 'Kotlin Language Server для полноценного автодополнения кода на Kotlin, проверки синтаксиса и поиска определений.';
      case 'typescript-lsp':
        return 'Языковой сервер TypeScript/JavaScript для мгновенной подсветки типов, умного автодополнения и документации JSDoc/TS.';
      case 'markdown-lsp':
        return 'Marksman LSP: интеллектуальная навигация по Markdown-файлам, проверка ссылок, генерация оглавлений и быстрый предпросмотр.';
      case 'python-lsp':
        return 'Языковой сервер Pyright от Microsoft: быстрый статический анализ типов и контекстные подсказки для Python.';
      case 'clangd-lsp':
        return 'Clangd Language Server для C и C++: анализ кода на базе LLVM, подсветка ошибок в реальном времени и автодополнение.';
      case 'rust-lsp':
        return 'Инструменты Rust (rustc, cargo) и Rust Analyzer для умной работы с исходным кодом на языке Rust.';
      case 'go-lsp':
        return 'Компилятор Go и языковой сервер gopls для разработки серверных модулей и микросервисов.';
      case 'ripgrep':
        return 'Сверхбыстрая консольная утилита поиска по тексту и коду проекта (команда rg), работающая в десятки раз быстрее grep.';
      case 'gh-cli':
        return 'Официальный GitHub CLI (gh) для создания pull request, управления issues, репозиториями и релизами прямо из терминала.';
      case 'uv':
        return 'Сверхбыстрый менеджер пакетов и резолвер зависимостей для Python, написанный на Rust. Работает в 10-100 раз быстрее стандартного pip.';
      case 'bun':
        return 'Сверхбыстрый альтернативный рантайм JavaScript/TypeScript со встроенным бандлером, тест-раннером и пакетным менеджером.';
      case 'pnpm':
        return 'Быстрый и экономящий диск менеджер пакетов Node.js с использованием жестких ссылок и общего хранилища зависимостей.';
      case 'flutter-distributor':
        return 'Инструмент для автоматической сборки и публикации релизов Flutter приложений в APK, AAB, Web, Linux deb/tar и AppStore/PlayStore.';
      default:
        return pkg.description;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categoryColor = _getCategoryColor(package.category);
    final isInstalled = package.isInstalled;
    final statusColor = isInstalled ? const Color(0xFF10B981) : Colors.white38;
    final binaries = _getBinariesForPackage(package);
    final installPath = _getInstallPath(package);
    final detailedDesc = _getDetailedDescription(package);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isInstalled
                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                : categoryColor.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: categoryColor.withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            categoryColor.withValues(alpha: 0.25),
                            categoryColor.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: categoryColor.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(package.icon, color: categoryColor, size: 26),
                    ),
                    const SizedBox(width: 16),
                    // Titles and badges
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            package.name,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Category
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: categoryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: categoryColor.withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  package.category,
                                  style: GoogleFonts.inter(
                                    color: categoryColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Version
                              if (package.version != null && package.version!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.cyanAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.cyanAccent.withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    package.version!,
                                    style: GoogleFonts.jetBrainsMono(
                                      color: Colors.cyanAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isInstalled ? LucideIcons.badge_check : LucideIcons.circle_dashed,
                                      color: statusColor,
                                      size: 11,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isInstalled ? 'Установлен' : 'Не установлен',
                                      style: GoogleFonts.inter(
                                        color: statusColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Close button
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white54, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Scrollable Details
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // About section
                      _buildSectionHeader('О ПАКЕТЕ', LucideIcons.info, categoryColor),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Text(
                          detailedDesc,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Provided binaries
                      _buildSectionHeader('ПРЕДОСТАВЛЯЕМЫЕ КОМАНДЫ И БИНАРНИКИ', LucideIcons.terminal, categoryColor),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: binaries.map((bin) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2433),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.chevron_right, size: 12, color: Colors.cyanAccent),
                                const SizedBox(width: 4),
                                Text(
                                  bin,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // Install path
                      _buildSectionHeader('РАСПОЛОЖЕНИЕ В СИСТЕМЕ', LucideIcons.folder, categoryColor),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.hard_drive, size: 14, color: Colors.white54),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                installPath,
                                style: GoogleFonts.jetBrainsMono(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Installation Command Preview
                      _buildSectionHeader('КОМАНДА УСТАНОВКИ', LucideIcons.code, categoryColor),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0E14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'bash command',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: package.command));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Команда скопирована в буфер обмена'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    child: Row(
                                      children: [
                                        const Icon(LucideIcons.copy, size: 12, color: Colors.cyanAccent),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Скопировать',
                                          style: GoogleFonts.inter(
                                            color: Colors.cyanAccent,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              package.command,
                              maxLines: 4,
                              style: GoogleFonts.jetBrainsMono(
                                color: const Color(0xFF86EFAC),
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Actions Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Закрыть',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: Icon(
                          isInstalled ? LucideIcons.refresh_cw : LucideIcons.download,
                          size: 15,
                        ),
                        label: Text(
                          isInstalled ? 'Обновить / Переустановить' : 'Установить пакет',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          PackageInstallDialog.show(context, package, isUpdate: isInstalled);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isInstalled ? const Color(0xFF059669) : theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
