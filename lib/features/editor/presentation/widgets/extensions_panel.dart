import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/todo_tree_service.dart';
import 'package:quantum_ide/core/services/test_runner_service.dart';
import 'package:quantum_ide/core/services/dependency_checker_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class ExtensionsPanel extends ConsumerStatefulWidget {
  const ExtensionsPanel({super.key});

  @override
  ConsumerState<ExtensionsPanel> createState() => _ExtensionsPanelState();
}

class _ExtensionsPanelState extends ConsumerState<ExtensionsPanel> {
  int _selectedExtension = -1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      color: const Color(0xFF0D0F14).withValues(alpha: 0.7),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.cyanAccent, Colors.purpleAccent],
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.puzzle, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Extensions',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: _selectedExtension == -1
                ? _buildExtensionsList(l10n)
                : _buildExtensionView(_selectedExtension, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildExtensionsList(AppLocalizations l10n) {
    final extensions = [
      _ExtensionData(
        icon: LucideIcons.list_todo,
        name: 'Todo Tree',
        description: 'Find all TODO, FIXME, HACK comments',
        color: Colors.amberAccent,
        badge: null,
      ),
      _ExtensionData(
        icon: LucideIcons.play,
        name: 'Test Runner',
        description: 'Run and view test results',
        color: Colors.greenAccent,
        badge: null,
      ),
      _ExtensionData(
        icon: LucideIcons.package,
        name: 'Dependency Checker',
        description: 'Check for outdated packages',
        color: Colors.orangeAccent,
        badge: null,
      ),
      _ExtensionData(
        icon: LucideIcons.code,
        name: 'Snippets',
        description: 'Code snippets for Flutter/Dart',
        color: Colors.cyanAccent,
        badge: null,
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: extensions.length,
      itemBuilder: (context, index) {
        final ext = extensions[index];
        return _buildExtensionCard(ext, index);
      },
    );
  }

  Widget _buildExtensionCard(_ExtensionData ext, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedExtension = index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ext.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(ext.icon, size: 18, color: ext.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ext.name,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ext.description,
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevron_right, size: 14, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExtensionView(int index, AppLocalizations l10n) {
    switch (index) {
      case 0:
        return _buildTodoTreeView(l10n);
      case 1:
        return _buildTestRunnerView(l10n);
      case 2:
        return _buildDependencyCheckerView(l10n);
      case 3:
        return _buildSnippetsView(l10n);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => setState(() => _selectedExtension = -1),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrow_left, size: 12, color: Colors.white54),
            const SizedBox(width: 4),
            Text('Back', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoTreeView(AppLocalizations l10n) {
    final todoState = ref.watch(todoTreeProvider);

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => ref.read(todoTreeProvider.notifier).scan(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.refresh_cw, size: 12, color: Colors.amberAccent),
                        const SizedBox(width: 6),
                        Text('Scan Project', style: GoogleFonts.inter(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (todoState.isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: Colors.amberAccent, strokeWidth: 2)))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: todoState.filtered.length,
              itemBuilder: (context, index) {
                final item = todoState.filtered[index];
                final typeColor = item.type == 'FIXME' || item.type == 'BUG'
                    ? Colors.redAccent
                    : item.type == 'TODO'
                        ? Colors.amberAccent
                        : Colors.purpleAccent;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Clipboard.setData(ClipboardData(text: '${item.filePath}:${item.line}\n${item.text}')),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(item.type, style: GoogleFonts.jetBrainsMono(color: typeColor, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.text,
                                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item.filePath}:${item.line}',
                                  style: GoogleFonts.jetBrainsMono(color: Colors.white30, fontSize: 9),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTestRunnerView(AppLocalizations l10n) {
    final testState = ref.watch(testRunnerProvider);

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: testState.isRunning ? null : () => ref.read(testRunnerProvider.notifier).runAll(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: testState.isRunning
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.greenAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (testState.isRunning)
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.greenAccent))
                        else
                          Icon(LucideIcons.play, size: 12, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Text(
                          testState.isRunning ? 'Running...' : 'Run All Tests',
                          style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (testState.results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                _buildTestBadge('${testState.passed} passed', Colors.greenAccent),
                const SizedBox(width: 8),
                _buildTestBadge('${testState.failed} failed', Colors.redAccent),
              ],
            ),
          ),
        Expanded(
          child: testState.results.isEmpty
              ? Center(
                  child: Text(
                    testState.isRunning ? 'Running tests...' : 'No test results yet',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: testState.results.length,
                  itemBuilder: (context, index) {
                    final result = testState.results[index];
                    final color = result.status == TestStatus.passed
                        ? Colors.greenAccent
                        : result.status == TestStatus.failed
                            ? Colors.redAccent
                            : Colors.orangeAccent;
                    final icon = result.status == TestStatus.passed
                        ? LucideIcons.circle_check
                        : result.status == TestStatus.failed
                            ? LucideIcons.circle_x
                            : LucideIcons.info;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Icon(icon, size: 12, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(result.name, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTestBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildDependencyCheckerView(AppLocalizations l10n) {
    final depState = ref.watch(dependencyCheckerProvider);

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: GestureDetector(
            onTap: depState.isLoading ? null : () => ref.read(dependencyCheckerProvider.notifier).check(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (depState.isLoading)
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orangeAccent))
                  else
                    Icon(LucideIcons.refresh_cw, size: 12, color: Colors.orangeAccent),
                  const SizedBox(width: 6),
                  Text(
                    depState.isLoading ? 'Checking...' : 'Check Dependencies',
                    style: GoogleFonts.inter(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: depState.dependencies.isEmpty
              ? Center(
                  child: Text(
                    depState.isLoading ? 'Scanning pubspec.yaml...' : 'No dependencies found',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: depState.dependencies.length,
                  itemBuilder: (context, index) {
                    final dep = depState.dependencies[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Icon(LucideIcons.package, size: 12, color: Colors.orangeAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dep.name, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500)),
                                Text(dep.currentVersion, style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 9)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: dep.status == DependencyStatus.upToDate
                                  ? Colors.greenAccent.withValues(alpha: 0.1)
                                  : Colors.orangeAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              dep.status == DependencyStatus.upToDate ? 'OK' : 'Outdated',
                              style: GoogleFonts.inter(
                                color: dep.status == DependencyStatus.upToDate ? Colors.greenAccent : Colors.orangeAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSnippetsView(AppLocalizations l10n) {
    final snippets = [
      _SnippetData('stless', 'StatelessWidget', Colors.cyanAccent),
      _SnippetData('stful', 'StatefulWidget', Colors.cyanAccent),
      _SnippetData('stlessp', 'ConsumerWidget', Colors.purpleAccent),
      _SnippetData('stfulp', 'ConsumerStatefulWidget', Colors.purpleAccent),
      _SnippetData('column', 'Column', Colors.white54),
      _SnippetData('row', 'Row', Colors.white54),
      _SnippetData('sized', 'SizedBox', Colors.white54),
      _SnippetData('padding', 'Padding', Colors.white54),
      _SnippetData('container', 'Container', Colors.white54),
      _SnippetData('provider', 'StateProvider', Colors.purpleAccent),
      _SnippetData('notifier', 'StateNotifier', Colors.purpleAccent),
      _SnippetData('async', 'Async Function', Colors.orangeAccent),
      _SnippetData('try', 'Try-Catch', Colors.orangeAccent),
      _SnippetData('push', 'Navigator.push', Colors.greenAccent),
      _SnippetData('text', 'Text Widget', Colors.white54),
      _SnippetData('btn', 'ElevatedButton', Colors.white54),
      _SnippetData('model', 'Data Model', Colors.cyanAccent),
      _SnippetData('test', 'Test Case', Colors.greenAccent),
      _SnippetData('testwidget', 'Widget Test', Colors.greenAccent),
    ];

    return Column(
      children: [
        _buildBackButton(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            'Type prefix in editor to insert snippet',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: snippets.length,
            itemBuilder: (context, index) {
              final s = snippets[index];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: s.prefix)),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: s.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(s.prefix, style: GoogleFonts.jetBrainsMono(color: s.color, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(s.name, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExtensionData {
  final IconData icon;
  final String name;
  final String description;
  final Color color;
  final String? badge;

  const _ExtensionData({
    required this.icon,
    required this.name,
    required this.description,
    required this.color,
    this.badge,
  });
}

class _SnippetData {
  final String prefix;
  final String name;
  final Color color;

  const _SnippetData(this.prefix, this.name, this.color);
}
