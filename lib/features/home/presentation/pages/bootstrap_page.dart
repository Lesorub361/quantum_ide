import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

enum DevStack {
  web(
    'Web (JavaScript / TypeScript)',
    'Websites and web apps with HTML, CSS, and JS frameworks.',
    'Уже в образе: Node.js, npm, Git',
    ['node', 'npm', 'git'],
    isPreinstalled: true,
  ),
  python(
    'Python',
    'Scripts, automation, data work, and Python backends.',
    'Python 3 в образе; доустанавливается: pip, venv',
    ['python3', 'python3-pip', 'python3-venv'],
    isPreinstalled: true,
  ),
  android(
    'Android / Flutter (JDK 17)',
    'Build Android APK/AAB and Flutter projects directly on device.',
    'JDK 17 и Flutter в образе; доустанавливается при необходимости',
    ['openjdk-17-jdk-headless', 'gradle', 'flutter'],
    isPreinstalled: true,
  ),
  java21(
    'Java 21 (OpenJDK 21 LTS)',
    'Modern Java 21 for AGP 8.5+, Gradle 8.10+, and Spring Boot.',
    'Доустанавливается: openjdk-21-jdk-headless',
    ['openjdk-21-jdk-headless'],
  ),
  cpp(
    'C / C++',
    'Fast compiled programs, algorithms, and systems code.',
    'Clang/CMake в образе; доустанавливается: gcc, g++, make, gdb',
    ['gcc', 'g++', 'make', 'cmake', 'gdb'],
  ),
  go(
    'Go (Golang)',
    'Fast CLI tools, microservices, and backend APIs.',
    'Доустанавливается: golang-go',
    ['golang-go'],
  ),
  rust(
    'Rust (rustc + cargo)',
    'Systems programming, CLI, and WebAssembly.',
    'Доустанавливается: rustc, cargo',
    ['rustc', 'cargo'],
  ),
  php(
    'PHP',
    'Websites and apps with PHP — classic sites and Laravel projects.',
    'Доустанавливается: php-cli, composer',
    ['php-cli', 'composer'],
  );

  final String label;
  final String description;
  final String installsSummary;
  final List<String> packages;
  final bool isPreinstalled;

  const DevStack(
    this.label,
    this.description,
    this.installsSummary,
    this.packages, {
    this.isPreinstalled = false,
  });
}

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  int _currentStep = 0; // 0: welcome & stacks, 1: installing, 2: Ubuntu 24.04 upgrade
  final Set<DevStack> _selectedStacks = {DevStack.web, DevStack.python};
  bool _isChecking = true;
  bool _isMigrating = false;
  String? _migrationError;
  Map<String, String>? _upgradeEnv;
  final List<String> _logLines = [];
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialState();
    });
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _checkInitialState() async {
    final runtime = ref.read(runtimeServiceProvider);
    
    // Check if runtime is already configured and ready
    if (runtime.isInitialized) {
      _finishBootstrap();
      return;
    }

    // Check if rootfs already exists on disk
    final isComplete = await runtime.isBootstrapComplete();
    if (isComplete) {
      await runtime.init();
      if (Platform.isAndroid || Platform.isIOS) {
        final env = await runtime.inspectEnvironment();
        if (env['needsUpgrade'] == 'true' && mounted) {
          setState(() {
            _upgradeEnv = env;
            _currentStep = 2;
            _isChecking = false;
          });
          return;
        }
      }
      if (mounted) {
        _finishBootstrap();
      }
      return;
    }

    // First run: show setup wizard
    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  Future<void> _startBootstrap() async {
    setState(() {
      _currentStep = 1;
    });

    final runtime = ref.read(runtimeServiceProvider);

    _addLog('Checking device architecture: ${Platform.operatingSystem} ${Platform.version.split(' ').first}');
    _addLog('Selected dev stacks: ${_selectedStacks.map((s) => s.name).join(', ')}');

    try {
      _addLog('Initializing QuantumIDE runtime environment...');
      await runtime.init();

      if (!runtime.isInitialized) {
        throw Exception(runtime.status.startsWith('Error:') ? runtime.status : 'Runtime initialization failed: ${runtime.status}');
      }

      _addLog('Runtime core prepared successfully.');
      _addLog('Setting up packages for selected toolchains...');

      final candidateAptPackages = <String>{};
      for (final stack in _selectedStacks) {
        _addLog('Configuring stack: ${stack.label} (${stack.packages.join(', ')})');
        for (final pkg in stack.packages) {
          if (pkg != 'node' && pkg != 'npm' && pkg != 'git' && pkg != 'flutter' && pkg != 'gradle') {
            candidateAptPackages.add(pkg);
          }
        }
      }

      final aptPackages = <String>[];
      if (candidateAptPackages.isNotEmpty) {
        _addLog('Checking packages already present in rootfs image...');
        for (final pkg in candidateAptPackages) {
          final checkRes = await runtime.runCommand('dpkg -s $pkg >/dev/null 2>&1 && echo INSTALLED || echo MISSING');
          if (checkRes.contains('INSTALLED')) {
            _addLog('✓ $pkg already pre-installed in image — skipped');
          } else {
            aptPackages.add(pkg);
          }
        }
      }

      if (aptPackages.isNotEmpty) {
        _addLog('Installing missing toolchain packages: ${aptPackages.join(' ')}...');
        final cmd = 'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y --no-install-recommends ${aptPackages.join(' ')}';
        _addLog('\$ $cmd');
        final job = runtime.runCommandStream(
          cmd,
          onLine: (line, {bool isError = false, bool replace = false}) {
            if (line.trim().isEmpty) return;
            _addLog(line, replace: replace);
          },
        );
        final code = await job.exitCode;
        if (code == 0) {
          _addLog('✓ Toolchain packages installed successfully.');
        } else {
          _addLog('⚠ apt exited with code $code (packages can be installed later from Packages)');
        }
      } else {
        _addLog('✓ All selected packages are already present in the image.');
      }

      _addLog('Setup completed! Loading workspace...');
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        _finishBootstrap();
      }
    } catch (e) {
      _addLog('Bootstrap error: $e');
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _addLog(String line, {bool replace = false}) {
    if (!mounted) return;
    setState(() {
      if (replace && _logLines.isNotEmpty) {
        _logLines[_logLines.length - 1] = line;
      } else {
        _logLines.add(line);
      }
      if (_logLines.length > 3000) _logLines.removeRange(0, 500);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _finishBootstrap() async {
    try {
      await ref.read(workspaceProvider.notifier).restoreLastWorkspace();
    } catch (e) {
      debugPrint('Failed to restore last workspace: $e');
    }
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runtime = ref.watch(runtimeServiceProvider);

    if (_isChecking) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary)),
              const SizedBox(height: 16),
              Text(
                'Checking environment…',
                style: GoogleFonts.inter(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: _buildStepContent(context, theme, runtime),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(BuildContext context, ThemeData theme, RuntimeService runtime) {
    switch (_currentStep) {
      case 0:
        return _buildStackSelectionStep(context, theme);
      case 2:
        return _buildUpgradeStep(context, theme, runtime);
      case 1:
      default:
        return _buildInstallingStep(context, theme, runtime);
    }
  }

  Widget _buildUpgradeStep(BuildContext context, ThemeData theme, RuntimeService runtime) {
    final currentOs = _upgradeEnv?['os'] ?? 'Ubuntu 20.04';
    final currentGlibc = _upgradeEnv?['glibc'] ?? '2.31';
    final currentFlutter = _upgradeEnv?['flutter'] ?? '3.47.8';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(LucideIcons.sparkles, color: Colors.amberAccent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Доступно обновление Linux-среды',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Новый образ Ubuntu 24.04 LTS + Flutter 3.50.0',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.amberAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Текущая среда: $currentOs · GLIBC $currentGlibc · Flutter $currentFlutter',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                const Text('• Ubuntu 20.04 → Ubuntu 24.04 LTS (Noble)', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                const Text('• GLIBC 2.31 → GLIBC 2.39 (нужно для Dart 3.14 / Flutter 3.50+)', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                const Text('• Включены: Git, Node.js, Python 3, Clang/CMake, JDK 17, Flutter 3.50', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                Text(
                  'Ваши проекты (/root/projects), .ssh, .gitconfig, .gemini и настройки сохранятся автоматически.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: Colors.greenAccent, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_isMigrating) ...[
            LinearProgressIndicator(
              value: runtime.progress > 0 ? runtime.progress : null,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 10),
            Text(
              runtime.status,
              style: GoogleFonts.jetBrainsMono(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_migrationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _migrationError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
          ],
          if (!_isMigrating || _migrationError != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _finishBootstrap,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Позже'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () async {
                      setState(() {
                        _isMigrating = true;
                        _migrationError = null;
                      });
                      try {
                        await ref.read(runtimeServiceProvider).migrateToUbuntu2404();
                        if (mounted) {
                          _finishBootstrap();
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _migrationError = '$e';
                          });
                        }
                      }
                    },
                    icon: const Icon(LucideIcons.download, size: 18),
                    label: const Text('Обновить до Ubuntu 24.04'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Step 1: Hardware overview & Toolchain selection (Mobile-Harness style)
  Widget _buildStackSelectionStep(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          // Logo & Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.terminal, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QuantumIDE Setup',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Guided Private Development Runtime',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Device compatibility badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.cpu, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Environment: ${Platform.operatingSystem.toUpperCase()} · Rootfs Ubuntu 24.04 ready',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Icon(LucideIcons.badge_check, size: 16, color: Colors.greenAccent.shade400),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Select Development Stacks',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'В образ уже вшиты: Git, Node.js, Python 3, Clang/CMake, JDK 17 и Flutter. Выберите, что нужно доустановить (уже установленное пропустится автоматически):',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),

          // DevStack cards
          for (final stack in DevStack.values) ...[
            _buildStackCard(theme, stack),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 24),

          // Next Button
          ElevatedButton(
            onPressed: _startBootstrap,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Install & Launch Runtime',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.arrow_right, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStackCard(ThemeData theme, DevStack stack) {
    final isSelected = _selectedStacks.contains(stack);

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedStacks.remove(stack);
          } else {
            _selectedStacks.add(stack);
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedStacks.add(stack);
                  } else {
                    _selectedStacks.remove(stack);
                  }
                });
              },
              activeColor: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stack.label,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (stack.isPreinstalled)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            'В образе',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.greenAccent.shade200,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stack.description,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stack.installsSummary,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: stack.isPreinstalled
                          ? Colors.greenAccent.shade200.withValues(alpha: 0.9)
                          : theme.colorScheme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 3: Installing & Live Terminal Log
  Widget _buildInstallingStep(BuildContext context, ThemeData theme, RuntimeService runtime) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
            const SizedBox(width: 12),
            Text(
              'Configuring Runtime Environment',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          runtime.status,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: runtime.progress > 0 ? runtime.progress : null,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(4),
          minHeight: 6,
        ),
        const SizedBox(height: 20),

        // Live Log Terminal
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: ListView.builder(
              controller: _logScroll,
              itemCount: _logLines.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '› ${_logLines[index]}',
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white70,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (runtime.status.startsWith('Error')) ...[
          ElevatedButton(
            onPressed: _startBootstrap,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Retry Setup'),
          ),
        ],
      ],
    );
  }
}
