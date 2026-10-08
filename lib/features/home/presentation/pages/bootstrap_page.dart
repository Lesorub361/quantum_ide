import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/agent_activity_widgets.dart';

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  int _currentStep = 0; // 0: welcome & stacks, 1: agent choice, 2: installing
  final Set<DevStack> _selectedStacks = {DevStack.web, DevStack.python};
  AgentKind _selectedAgent = AgentKind.antigravity;
  bool _isChecking = true;
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
      _currentStep = 2;
    });

    final runtime = ref.read(runtimeServiceProvider);
    ref.read(aiProvider.notifier).setAgentKind(_selectedAgent);

    _addLog('Checking device architecture: ${Platform.operatingSystem} ${Platform.version.split(' ').first}');
    _addLog('Selected dev stacks: ${_selectedStacks.map((s) => s.name).join(', ')}');
    _addLog('Selected default agent: ${_selectedAgent.title}');

    try {
      _addLog('Initializing QuantumIDE runtime environment...');
      await runtime.init();

      if (!runtime.isInitialized) {
        throw Exception(runtime.status.startsWith('Error:') ? runtime.status : 'Runtime initialization failed: ${runtime.status}');
      }

      _addLog('Runtime core prepared successfully.');
      _addLog('Setting up packages for selected toolchains...');

      final aptPackages = <String>{};
      for (final stack in _selectedStacks) {
        _addLog('Configuring stack: ${stack.label} (${stack.packages.join(', ')})');
        for (final pkg in stack.packages) {
          if (pkg != 'node' && pkg != 'npm' && pkg != 'git' && pkg != 'flutter' && pkg != 'gradle') {
            aptPackages.add(pkg);
          }
        }
      }

      if (aptPackages.isNotEmpty) {
        _addLog('Installing toolchain packages: ${aptPackages.join(' ')}...');
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
              AnimatedThinkingDots(dotColor: theme.colorScheme.primary, size: 6),
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
      case 1:
        return _buildAgentSelectionStep(context, theme);
      case 2:
      default:
        return _buildInstallingStep(context, theme, runtime);
    }
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
            'Core tools (Git, Node.js, bash) are always configured. Choose additional toolchains:',
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
            onPressed: () {
              setState(() {
                _currentStep = 1;
              });
            },
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
                  'Continue: Coding Agent',
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
                  Text(
                    stack.label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stack.description,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
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

  /// Step 2: Agent Selection (Mobile-Harness style)
  Widget _buildAgentSelectionStep(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _currentStep = 0),
                icon: const Icon(LucideIcons.arrow_left, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                'Default Coding Agent',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Choose which autonomous AI CLI engine to use for project automation, building, and chat:',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          for (final agent in AgentKind.values) ...[
            _buildAgentCard(theme, agent),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),

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
                const Icon(LucideIcons.sparkles, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentCard(ThemeData theme, AgentKind agent) {
    final isSelected = _selectedAgent == agent;

    return InkWell(
      onTap: () => setState(() => _selectedAgent = agent),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        agent.title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          agent.downloadNote,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agent.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
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
            AnimatedThinkingDots(dotColor: theme.colorScheme.primary, size: 5),
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
