import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/cli_agent_bridge.dart';
import 'package:quantum_ide/core/services/cli_auth_service.dart';
import 'package:quantum_ide/core/services/cli_installer_service.dart';
import 'package:quantum_ide/core/services/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/model_selection_sheet.dart';

/// Formats Antigravity model identifiers into clean, human-friendly names (from Mobile-Harness).
String formatAntigravityModelName(String id) {
  switch (id) {
    case 'gemini-3.8-flash-high':
      return 'Gemini 3.8 Flash (High)';
    case 'gemini-3.8-flash-medium':
      return 'Gemini 3.8 Flash';
    case 'gemini-3.8-flash-low':
      return 'Gemini 3.8 Flash (Low)';
    case 'gemini-3.7-flash-high':
      return 'Gemini 3.7 Flash (High)';
    case 'gemini-3.7-flash-medium':
      return 'Gemini 3.7 Flash';
    case 'gemini-3.7-flash-low':
      return 'Gemini 3.7 Flash (Low)';
    case 'gemini-3.6-flash-high':
      return 'Gemini 3.6 Flash (High)';
    case 'gemini-3.6-flash-medium':
      return 'Gemini 3.6 Flash';
    case 'gemini-3.6-flash-low':
      return 'Gemini 3.6 Flash (Low)';
    case 'gemini-3.1-pro-high':
      return 'Gemini 3.1 Pro (High)';
    case 'gemini-3.1-pro-low':
      return 'Gemini 3.1 Pro (Low)';
    case 'claude-sonnet-4-6':
      return 'Claude 3.7 Sonnet';
    case 'claude-opus-4-6-thinking':
      return 'Claude 3.7 Opus (Thinking)';
    case 'gpt-oss-120b-medium':
      return 'GPT-OSS 120B';
    default:
      return id;
  }
}

/// Returns tier classification badges for Antigravity models (from Mobile-Harness).
String formatAntigravityModelTier(String id) {
  if (id.contains('3.8')) return 'Recommended';
  if (id.contains('3.6')) return 'Stable';
  if (id.contains('3.1-pro')) return 'Pro Reasoning';
  if (id.contains('claude')) return 'Anthropic';
  if (id.contains('gpt')) return 'Open Source';
  return '';
}

/// Диалог настроек CLI-агентов (Antigravity CLI, Claude Code, DeepSeek Harness)
/// Спроектирован строго по образцу Mobile-Harness с отдельным интерфейсом для каждого агента.
class CliAgentSettingsDialog extends ConsumerStatefulWidget {
  final AgentKind? initialKind;

  const CliAgentSettingsDialog({super.key, this.initialKind});

  static Future<void> show(BuildContext context, {AgentKind? initialKind}) {
    return showDialog(
      context: context,
      builder: (ctx) => CliAgentSettingsDialog(initialKind: initialKind),
    );
  }

  @override
  ConsumerState<CliAgentSettingsDialog> createState() => _CliAgentSettingsDialogState();
}

class _CliAgentSettingsDialogState extends ConsumerState<CliAgentSettingsDialog> {
  late AgentKind _selectedAgent;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  final _claudeKeyCtrl = TextEditingController();
  final _deepseekKeyCtrl = TextEditingController();
  final _openrouterKeyCtrl = TextEditingController();
  final _geminiKeyCtrl = TextEditingController();
  final _antigravityCodeCtrl = TextEditingController();
  String _currentAppVersion = '';

  @override
  void initState() {
    super.initState();
    final currentKind = ref.read(aiProvider).activeAgentKind;
    _selectedAgent = widget.initialKind ?? currentKind;

    final auth = ref.read(cliAuthProvider);
    _claudeKeyCtrl.text = auth.anthropicApiKey ?? '';
    _deepseekKeyCtrl.text = auth.deepseekApiKey ?? '';
    _openrouterKeyCtrl.text = auth.openRouterApiKey ?? '';
    _geminiKeyCtrl.text = auth.geminiApiKey ?? '';

    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentAppVersion = '${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _claudeKeyCtrl.dispose();
    _deepseekKeyCtrl.dispose();
    _openrouterKeyCtrl.dispose();
    _geminiKeyCtrl.dispose();
    _antigravityCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _testAgentConnection(AgentKind kind) async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final bridge = ref.read(cliAgentBridgeProvider);
      final binary = bridge.resolveBinary(kind);

      if (binary == null) {
        throw Exception('${kind.title} CLI не установлен в системе.');
      }

      if (kind == AgentKind.antigravity) {
        final res = await Process.run(binary, ['--print-timeout', '10s', '-p', 'ping']);
        stopwatch.stop();
        if (res.exitCode == 0) {
          setState(() {
            _testSuccess = true;
            _testResult = 'Связь с Antigravity CLI успешна (${stopwatch.elapsedMilliseconds} ms)';
          });
        } else {
          throw Exception(res.stderr.toString().isNotEmpty ? res.stderr.toString() : 'Ошибка запуска (код ${res.exitCode})');
        }
      } else if (kind == AgentKind.claudeCode) {
        final res = await Process.run(binary, ['--version']);
        stopwatch.stop();
        if (res.exitCode == 0) {
          setState(() {
            _testSuccess = true;
            _testResult = 'Claude Code обнаружен: ${res.stdout.toString().trim()} (${stopwatch.elapsedMilliseconds} ms)';
          });
        } else {
          throw Exception(res.stderr.toString().isNotEmpty ? res.stderr.toString() : 'Код ${res.exitCode}');
        }
      } else {
        final res = await Process.run(binary, ['--help']);
        stopwatch.stop();
        if (res.exitCode == 0) {
          setState(() {
            _testSuccess = true;
            _testResult = 'DeepSeek Harness готов (${stopwatch.elapsedMilliseconds} ms)';
          });
        } else {
          throw Exception(res.stderr.toString().isNotEmpty ? res.stderr.toString() : 'Код ${res.exitCode}');
        }
      }
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _testSuccess = false;
        _testResult = 'Ошибка проверки: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(cliAuthProvider);
    final activeModel = ref.watch(activeAiModelProvider);
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Dialog(
      backgroundColor: const Color(0xFF131824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 620,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Dialog Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selectedAgent.brandColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_selectedAgent.icon, size: 18, color: _selectedAgent.brandColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Настройки автономных CLI агентов',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Архитектура Mobile-Harness (изолированный бекенд и драйвер)',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 18, color: Colors.white54),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),

            // ── Agent Selector Segmented Tabs ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    _buildAgentTab(AgentKind.antigravity, 'Antigravity CLI', LucideIcons.sparkles, Colors.purpleAccent),
                    _buildAgentTab(AgentKind.claudeCode, 'Claude Code', LucideIcons.bot, Colors.amberAccent),
                    _buildAgentTab(AgentKind.deepseekHarness, 'DeepSeek Harness', LucideIcons.brain_circuit, Colors.cyanAccent),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Main Body per Selected Agent ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selectedAgent == AgentKind.antigravity)
                      _buildAntigravityInterface(context, auth, activeModel)
                    else if (_selectedAgent == AgentKind.claudeCode)
                      _buildClaudeInterface(context, auth, activeModel)
                    else
                      _buildDeepSeekInterface(context, auth, activeModel),

                    const SizedBox(height: 14),

                    // Runtime & CLI Installation (Mobile-Harness architecture)
                    _buildCliRuntimeCard(_selectedAgent),

                    const SizedBox(height: 14),

                    // App Updates (Mobile-Harness AppUpdater architecture)
                    _buildAppUpdatesCard(),

                    const SizedBox(height: 14),

                    // Test Connection Banner
                    if (_testResult != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: _testSuccess
                              ? Colors.greenAccent.withValues(alpha: 0.12)
                              : Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _testSuccess
                                ? Colors.greenAccent.withValues(alpha: 0.3)
                                : Colors.redAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _testSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                              size: 16,
                              color: _testSuccess ? Colors.greenAccent : Colors.redAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _testResult!,
                                style: GoogleFonts.inter(
                                  color: _testSuccess ? Colors.greenAccent : Colors.redAccent,
                                  fontSize: 11,
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

            // ── Dialog Footer ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isTesting ? null : () => _testAgentConnection(_selectedAgent),
                    icon: _isTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                          )
                        : const Icon(LucideIcons.activity, size: 14),
                    label: Text(_isTesting ? 'Проверка...' : 'Проверить связь'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      ref.read(aiProvider.notifier).setAgentKind(_selectedAgent);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedAgent.brandColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: Text('Выбрать агента', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentTab(AgentKind kind, String label, IconData icon, Color color) {
    final isSelected = _selectedAgent == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedAgent = kind;
            _testResult = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.4) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? color : Colors.white54),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white60,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // 1. ANTIGRAVITY CLI DEDICATED INTERFACE (Mobile-Harness AgentAntigravityCard)
  // ═══════════════════════════════════════════════════════════════════════════════
  Widget _buildAntigravityInterface(BuildContext context, CliAuthState auth, String activeModel) {
    final isConnected = auth.isGoogleAuthenticated;
    final email = auth.googleAccountEmail;
    final effectiveModel = activeModel.isNotEmpty ? activeModel : 'gemini-3.8-flash-high';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Google Account Bento Card ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Google account',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),

              // Google Account Row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34A853).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF34A853).withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'G',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF34A853),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email ?? (isConnected ? 'Подключен' : 'Не выполнен вход'),
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isConnected ? 'Подключено через Google' : 'Требуется для работы Antigravity',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isConnected ? const Color(0xFF2E9D72) : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isConnected)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await ref.read(cliAuthProvider.notifier).startAntigravityLogin();
                          },
                          child: Text(
                            'Сменить аккаунт',
                            style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await ref.read(cliAuthProvider.notifier).logoutAntigravity();
                          },
                          child: Text(
                            'Выйти',
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // Authentication actions if not signed in
              if (!isConnected) ...[
                if (auth.antigravityStatus == AntigravityAuthStatus.starting ||
                    auth.antigravityStatus == AntigravityAuthStatus.completing) ...[
                  const LinearProgressIndicator(
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.purpleAccent),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.antigravityMessage ?? 'Авторизация в Google...',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.purpleAccent.shade100),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          ref.read(cliAuthProvider.notifier).launchInteractiveTerminal();
                        },
                        icon: const Icon(LucideIcons.terminal, size: 14),
                        label: const Text('Открыть в терминале'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          ref.read(cliAuthProvider.notifier).logoutAntigravity();
                        },
                        child: Text(
                          'Отмена',
                          style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ] else if (auth.antigravityStatus == AntigravityAuthStatus.awaitingCode) ...[
                  if (auth.antigravityAuthUrl != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(auth.antigravityAuthUrl!);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else {
                                Clipboard.setData(ClipboardData(text: auth.antigravityAuthUrl!));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(LucideIcons.external_link, size: 14),
                            label: const Text('Открыть в браузере'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.purpleAccent,
                              side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Скопировать ссылку',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: auth.antigravityAuthUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ссылка авторизации скопирована')),
                            );
                          },
                          icon: const Icon(LucideIcons.copy, size: 16, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _antigravityCodeCtrl,
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Одноразовый код авторизации (ключ)',
                      labelStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                      hintText: 'Вставьте код из браузера Google...',
                      hintStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white24),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      final code = _antigravityCodeCtrl.text.trim();
                      if (code.isNotEmpty) {
                        ref.read(cliAuthProvider.notifier).submitAntigravityCode(code);
                        _antigravityCodeCtrl.clear();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Завершить вход', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ] else ...[
                  if (auth.antigravityMessage != null && auth.antigravityStatus == AntigravityAuthStatus.error) ...[
                    Text(
                      auth.antigravityMessage!,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ref.read(cliAuthProvider.notifier).startAntigravityLogin();
                          },
                          icon: const Icon(LucideIcons.log_in, size: 16),
                          label: Text(
                            auth.antigravityStatus == AntigravityAuthStatus.error ? 'Переподключить' : 'Войти через Google',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF34A853),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          ref.read(cliAuthProvider.notifier).launchInteractiveTerminal();
                        },
                        icon: const Icon(LucideIcons.terminal, size: 14),
                        label: const Text('Терминал'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Active Intelligence Model Tile ──
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Активная модель',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                    ),
                    InkWell(
                      onTap: auth.isAntigravityModelsLoading
                          ? null
                          : () => ref.read(cliAuthProvider.notifier).syncAntigravityModels(),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (auth.isAntigravityModelsLoading)
                              const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.purpleAccent),
                              )
                            else
                              const Icon(LucideIcons.refresh_cw, size: 11, color: Colors.purpleAccent),
                            const SizedBox(width: 4),
                            Text(
                              'Синхронизировать',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.purpleAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _showAntigravityModelPickerModal(context, auth.antigravityModels, effectiveModel),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.purpleAccent.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(LucideIcons.sparkles, size: 16, color: Colors.purpleAccent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formatAntigravityModelName(effectiveModel),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    effectiveModel,
                                    style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white54),
                                  ),
                                  if (formatAntigravityModelTier(effectiveModel).isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.purpleAccent.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        formatAntigravityModelTier(effectiveModel),
                                        style: GoogleFonts.inter(fontSize: 9, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.chevron_right, size: 16, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Reasoning Effort Capsules ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Глубина мышления (Reasoning Effort)',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildEffortCapsule('low', 'Низкая (Fast)'),
                    const SizedBox(width: 8),
                    _buildEffortCapsule('medium', 'Средняя (Balanced)'),
                    const SizedBox(width: 8),
                    _buildEffortCapsule('high', 'Высокая (Deep)'),
                  ],
                ),
              ],
            ),
          ),
        ],
    );
  }

  void _showAntigravityModelPickerModal(BuildContext context, List<String> models, String currentModel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Модели Antigravity CLI',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(LucideIcons.x, size: 18, color: Colors.white54),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: models.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (c, idx) {
                    final m = models[idx];
                    final isSel = m == currentModel;
                    final tier = formatAntigravityModelTier(m);
                    return ListTile(
                      dense: true,
                      onTap: () {
                        ref.read(activeAiModelProvider.notifier).state = m;
                        Navigator.pop(ctx);
                      },
                      leading: Icon(
                        isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSel ? Colors.purpleAccent : Colors.white38,
                        size: 16,
                      ),
                      title: Text(
                        formatAntigravityModelName(m),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Colors.purpleAccent : Colors.white,
                        ),
                      ),
                      subtitle: Text(m, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white38)),
                      trailing: tier.isNotEmpty
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purpleAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tier,
                                style: GoogleFonts.inter(fontSize: 9.5, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEffortCapsule(String val, String label) {
    final auth = ref.watch(cliAuthProvider);
    final isSelected = auth.antigravityEffort == val;

    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(cliAuthProvider.notifier).setAntigravityEffort(val),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.purpleAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.purpleAccent : Colors.white10,
              width: isSelected ? 1.2 : 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // 2. CLAUDE CODE INTERFACE (Modes: OAuth Subscription / Anthropic API / OpenRouter)
  // ═══════════════════════════════════════════════════════════════════════════════
  Widget _buildClaudeInterface(BuildContext context, CliAuthState auth, String activeModel) {
    final mode = auth.claudeProviderType;
    final isSubscription = mode == 'claude_subscription';
    final isOpenRouter = mode == 'openrouter';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode Selector Tabs
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _buildClaudeModeTab('claude_subscription', 'OAuth / Подписка', '👑'),
              _buildClaudeModeTab('anthropic', 'Anthropic API', '🧠'),
              _buildClaudeModeTab('openrouter', 'OpenRouter', '🌐'),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Key Input if API key based
        if (!isSubscription) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOpenRouter ? 'OpenRouter API Key:' : 'Anthropic API Key:',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: isOpenRouter ? _openrouterKeyCtrl : _claudeKeyCtrl,
                  obscureText: true,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                  onChanged: (val) {
                    if (isOpenRouter) {
                      ref.read(cliAuthProvider.notifier).setOpenRouterApiKey(val.trim());
                    } else {
                      ref.read(cliAuthProvider.notifier).setAnthropicApiKey(val.trim());
                    }
                  },
                  decoration: InputDecoration(
                    hintText: isOpenRouter ? 'sk-or-v1-...' : 'sk-ant-...',
                    hintStyle: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info, size: 16, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Используется подписка Claude Code (OAuth). Для первичного входа запустите /login в терминале.',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.amberAccent.shade100),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Model Picker for Claude
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Модель Claude Code',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final providerId = isOpenRouter ? 'openrouter' : 'anthropic';
                  final selected = await showModelPickerModal(
                    context,
                    providerId: providerId,
                    currentModel: activeModel,
                    apiKey: isOpenRouter ? auth.openRouterApiKey : auth.anthropicApiKey,
                  );
                  if (selected != null) {
                    ref.read(activeAiModelProvider.notifier).state = selected;
                    await ref.read(aiServiceProvider).setModel(selected);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.bot, size: 16, color: Colors.amberAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          activeModel.isNotEmpty ? activeModel : 'claude-3-7-sonnet-20250219',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const Icon(LucideIcons.chevron_right, size: 16, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClaudeModeTab(String mode, String label, String emoji) {
    final auth = ref.watch(cliAuthProvider);
    final isSelected = auth.claudeProviderType == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await ref.read(cliAuthProvider.notifier).setClaudeProvider(mode);
          final defaultM = mode == 'openrouter' ? 'anthropic/claude-3.7-sonnet' : 'claude-3-7-sonnet-20250219';
          ref.read(activeAiModelProvider.notifier).state = defaultM;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFD97706).withValues(alpha: 0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFFD97706) : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // 3. DEEPSEEK HARNESS INTERFACE (All Providers & Custom API from Mobile-Harness)
  // ═══════════════════════════════════════════════════════════════════════════════
  Widget _buildDeepSeekInterface(BuildContext context, CliAuthState auth, String activeModel) {
    final provider = auth.deepseekProviderType;
    final isOpenRouter = provider == 'openrouter';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Backend Provider Selection Chips (from Mobile-Harness)
        Text(
          'Бекенд-провайдер DeepSeek Harness',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildDeepSeekProviderChip('deepseek', 'DeepSeek Official', '🐳'),
            _buildDeepSeekProviderChip('openrouter', 'OpenRouter', '🌐'),
            _buildDeepSeekProviderChip('anthropic', 'Anthropic', '🧠'),
            _buildDeepSeekProviderChip('kimi', 'Kimi (Moonshot)', '🌙'),
            _buildDeepSeekProviderChip('opencode_zen', 'OpenCode Zen', '⚡'),
            _buildDeepSeekProviderChip('nvidia', 'NVIDIA NIM', '💚'),
            _buildDeepSeekProviderChip('custom', 'Custom API', '⚙️'),
          ],
        ),

        const SizedBox(height: 14),

        // API Key Input
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOpenRouter ? 'OpenRouter API Key:' : 'API Key для $provider:',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: isOpenRouter ? _openrouterKeyCtrl : _deepseekKeyCtrl,
                obscureText: true,
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                onChanged: (val) {
                  if (isOpenRouter) {
                    ref.read(cliAuthProvider.notifier).setOpenRouterApiKey(val.trim());
                  } else {
                    ref.read(cliAuthProvider.notifier).setDeepSeekApiKey(val.trim());
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Введите ваш ключ...',
                  hintStyle: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Model Picker for DeepSeek
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Модель DeepSeek Harness',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final selected = await showModelPickerModal(
                    context,
                    providerId: provider,
                    currentModel: activeModel,
                    apiKey: isOpenRouter ? auth.openRouterApiKey : auth.deepseekApiKey,
                  );
                  if (selected != null) {
                    ref.read(activeAiModelProvider.notifier).state = selected;
                    await ref.read(aiServiceProvider).setModel(selected);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.brain_circuit, size: 16, color: Colors.cyanAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          activeModel.isNotEmpty ? activeModel : 'deepseek-chat',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const Icon(LucideIcons.chevron_right, size: 16, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeepSeekProviderChip(String providerId, String label, String emoji) {
    final auth = ref.watch(cliAuthProvider);
    final isSelected = auth.deepseekProviderType == providerId;

    return ChoiceChip(
      label: Text('$emoji $label'),
      selected: isSelected,
      onSelected: (val) async {
        await ref.read(cliAuthProvider.notifier).setDeepSeekProvider(providerId);
        final newDefault = AiProviders.byId(providerId).defaultModels.first;
        ref.read(activeAiModelProvider.notifier).state = newDefault;
      },
      selectedColor: Colors.cyanAccent.withValues(alpha: 0.25),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      labelStyle: GoogleFonts.inter(
        fontSize: 11,
        color: isSelected ? Colors.cyanAccent : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.6) : Colors.white10,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. CLI RUNTIME INSTALLATION & UPDATES (Mobile-Harness RuntimeInstaller)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCliRuntimeCard(AgentKind kind) {
    final installer = ref.watch(cliInstallerProvider);
    final installedVersion = installer.installedVersions[kind];
    final isInstalled = installedVersion != null && installedVersion.isNotEmpty;
    final updateInfo = installer.availableUpdates[kind];
    final hasUpdate = updateInfo?.hasUpdate ?? false;
    final isInstalling = installer.installingAgent == kind;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.terminal, size: 16, color: kind.brandColor),
                  const SizedBox(width: 8),
                  Text(
                    'Среда выполнения и CLI (${kind.title})',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: installer.isCheckingUpdates
                    ? null
                    : () => ref.read(cliInstallerProvider.notifier).checkCliUpdates(),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      if (installer.isCheckingUpdates)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
                        )
                      else
                        const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        'Проверить версии',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Status Row
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isInstalled ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isInstalled
                    ? 'Установлен ($installedVersion)'
                    : 'Не установлен в окружении',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isInstalled ? Colors.greenAccent : Colors.white60,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (hasUpdate) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Доступно: v${updateInfo!.latestVersion}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amberAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (isInstalling) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: installer.installProgress > 0 ? installer.installProgress : null,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(kind.brandColor),
            ),
            const SizedBox(height: 6),
            Text(
              installer.statusMessage ?? 'Установка...',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
            ),
          ],

          if (installer.errorMessage != null && installer.installingAgent == null) ...[
            const SizedBox(height: 8),
            Text(
              installer.errorMessage!,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent),
            ),
          ],

          const SizedBox(height: 12),

          // Install / Update Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isInstalling
                  ? null
                  : () => ref.read(cliInstallerProvider.notifier).installOrUpdateAgent(kind),
              icon: Icon(
                hasUpdate ? LucideIcons.arrow_up : (isInstalled ? LucideIcons.refresh_cw : LucideIcons.download),
                size: 14,
              ),
              label: Text(
                isInstalling
                    ? 'Установка...'
                    : (hasUpdate
                        ? 'Обновить до v${updateInfo!.latestVersion}'
                        : (isInstalled ? 'Переустановить / Проверить' : 'Установить ${kind.title} CLI')),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kind.brandColor.withValues(alpha: 0.25),
                foregroundColor: Colors.white,
                side: BorderSide(color: kind.brandColor.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. QUANTUM IDE APP UPDATES (Mobile-Harness AppUpdater)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildAppUpdatesCard() {
    final appUpdate = ref.watch(appUpdateServiceProvider);
    final updateInfo = appUpdate.updateInfo;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.sparkles, size: 16, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Обновление QuantumIDE',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Text(
                _currentAppVersion.isNotEmpty ? 'v$_currentAppVersion' : '',
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Автоматическая проверка новых релизов приложения и установка APK (система Mobile-Harness).',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
          ),

          if (appUpdate.isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: appUpdate.downloadProgress > 0 ? appUpdate.downloadProgress : null,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  appUpdate.statusMessage ?? 'Загрузка APK...',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                ),
                if (appUpdate.speedBytesPerSec > 0)
                  Text(
                    '${(appUpdate.speedBytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s',
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.cyanAccent),
                  ),
              ],
            ),
          ] else if (updateInfo != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.arrow_up, size: 16, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Text(
                        'Доступна версия ${updateInfo.versionName} (сборка ${updateInfo.versionCode})',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                  if (updateInfo.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      updateInfo.notes,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => ref.read(appUpdateServiceProvider.notifier).downloadAndInstallUpdate(updateInfo),
                icon: const Icon(LucideIcons.download, size: 14),
                label: Text(
                  'Загрузить и обновить приложение',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            if (appUpdate.statusMessage != null) ...[
              Text(
                appUpdate.statusMessage!,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.greenAccent),
              ),
              const SizedBox(height: 8),
            ],
            if (appUpdate.errorMessage != null) ...[
              Text(
                appUpdate.errorMessage!,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: appUpdate.isChecking
                    ? null
                    : () => ref.read(appUpdateServiceProvider.notifier).checkForUpdates(),
                icon: appUpdate.isChecking
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
                      )
                    : const Icon(LucideIcons.refresh_cw, size: 14),
                label: Text(
                  appUpdate.isChecking ? 'Проверка...' : 'Проверить обновления приложения',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
