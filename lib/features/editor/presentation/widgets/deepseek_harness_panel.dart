import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:quantum_ide/core/services/deepseek_harness_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class DeepSeekHarnessPanel extends ConsumerStatefulWidget {
  const DeepSeekHarnessPanel({super.key});

  @override
  ConsumerState<DeepSeekHarnessPanel> createState() => _DeepSeekHarnessPanelState();
}

class _DeepSeekHarnessPanelState extends ConsumerState<DeepSeekHarnessPanel> {
  InAppWebViewController? _webViewController;
  bool _showLogs = false;

  @override
  Widget build(BuildContext context) {
    final dsh = ref.watch(deepseekHarnessServiceProvider);
    final settings = ref.watch(settingsProvider);
    final workspace = ref.watch(workspaceProvider);
    final projectPath = workspace.currentPath ?? '/data/user/0/com.agy/files';
    final projectName = projectPath.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Проект';

    return Container(
      color: const Color(0xFF0C0E15),
      child: Column(
        children: [
          // ── Header Bar ──────────────────────────────────────────────────────
          _buildTopBar(context, dsh, settings, projectPath, projectName),

          // ── Main Body ───────────────────────────────────────────────────────
          Expanded(
            child: dsh.isRunning
                ? _buildWebView(dsh)
                : _buildLaunchDashboard(context, dsh, settings, projectPath, projectName),
          ),

          // ── Optional Logs Drawer ────────────────────────────────────────────
          if (_showLogs) _buildLogsDrawer(dsh),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    DeepSeekHarnessService dsh,
    SettingsState settings,
    String projectPath,
    String projectName,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // Logo & Name
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(LucideIcons.bot, size: 14, color: Colors.purpleAccent),
          ),
          const SizedBox(width: 8),
          Text(
            'DeepSeek Harness',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),

          // Project Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.folder, size: 10, color: Colors.cyanAccent),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: dsh.isRunning
                  ? Colors.greenAccent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: dsh.isRunning
                    ? Colors.greenAccent.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: dsh.isRunning ? Colors.greenAccent : Colors.white38,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  dsh.isRunning ? 'Port :${dsh.port}' : 'Остановлен',
                  style: TextStyle(
                    color: dsh.isRunning ? Colors.greenAccent : Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // Actions
          if (dsh.isRunning) ...[
            IconButton(
              icon: const Icon(LucideIcons.rotate_cw, size: 13, color: Colors.white70),
              tooltip: 'Обновить страницу',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              onPressed: () => _webViewController?.reload(),
            ),
            IconButton(
              icon: const Icon(LucideIcons.square, size: 13, color: Colors.redAccent),
              tooltip: 'Остановить агент',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              onPressed: () => dsh.stopServer(),
            ),
          ],
          IconButton(
            icon: Icon(
              _showLogs ? LucideIcons.terminal : LucideIcons.file_text,
              size: 13,
              color: _showLogs ? Colors.cyanAccent : Colors.white60,
            ),
            tooltip: 'Логи процесса',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings_2, size: 13, color: Colors.white60),
            tooltip: 'API Ключи провайдеров',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            onPressed: () => _showApiKeysDialog(context, settings),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView(DeepSeekHarnessService dsh) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(dsh.serverUrl)),
      initialSettings: InAppWebViewSettings(
        transparentBackground: false,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
      },
    );
  }

  Widget _buildLaunchDashboard(
    BuildContext context,
    DeepSeekHarnessService dsh,
    SettingsState settings,
    String projectPath,
    String projectName,
  ) {
    final hasKey = settings.deepseekApiKey.isNotEmpty || settings.openrouterApiKey.isNotEmpty;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              // Glowing Icon
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.cyanAccent],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purpleAccent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.bot, color: Colors.black, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                'DeepSeek Harness Agent',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Автономный ИИ-разработчик для проекта «$projectName»',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 16),

              // Status Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF131722),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: Column(
                  children: [
                    _buildRow(
                      icon: LucideIcons.folder,
                      title: 'Рабочая папка:',
                      value: projectPath,
                      color: Colors.cyanAccent,
                    ),
                    const Divider(color: Colors.white10, height: 16),
                    _buildRow(
                      icon: LucideIcons.key_round,
                      title: 'DeepSeek API Key:',
                      value: settings.deepseekApiKey.isNotEmpty
                          ? 'Указан (••••••••)'
                          : 'Не указан',
                      color: settings.deepseekApiKey.isNotEmpty ? Colors.greenAccent : Colors.amberAccent,
                    ),
                    if (settings.openrouterApiKey.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildRow(
                        icon: LucideIcons.network,
                        title: 'OpenRouter Key:',
                        value: 'Указан (доступ ко всем моделям)',
                        color: Colors.greenAccent,
                      ),
                    ],
                  ],
                ),
              ),
              if (!hasKey) ...[
                const SizedBox(height: 8),
                const Text(
                  '💡 Совет: укажите DeepSeek или OpenRouter API ключ для доступа к моделям',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),

              // Launch Button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  icon: dsh.isStarting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.play, size: 16),
                  label: Text(
                    dsh.isStarting
                        ? 'Запуск сервера dsh web...'
                        : 'Запустить DeepSeek Harness',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: const Color(0xFF090D16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: dsh.isStarting
                      ? null
                      : () {
                          setState(() => _showLogs = true);
                          dsh.startServer(projectPath: projectPath, settings: settings);
                        },
                ),
              ),
              const SizedBox(height: 8),

              // Row with Update & Keys buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: dsh.isUpdating
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(color: Colors.purpleAccent, strokeWidth: 1.5),
                            )
                          : const Icon(LucideIcons.download, size: 13),
                      label: Text(
                        dsh.isUpdating ? 'Обновление...' : 'Обновить dsh',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purpleAccent,
                        side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: dsh.isUpdating
                          ? null
                          : () {
                              setState(() => _showLogs = true);
                              dsh.updateOrInstallDsh();
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(LucideIcons.key, size: 13),
                      label: const Text('Ввести ключи', style: TextStyle(fontSize: 11.5)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _showApiKeysDialog(context, settings),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogsDrawer(DeepSeekHarnessService dsh) {
    return Container(
      height: 140,
      width: double.infinity,
      color: const Color(0xFF07090F),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Логи процесса DeepSeek Harness',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              InkWell(
                onTap: () => dsh.clearLogs(),
                child: const Text('Очистить', style: TextStyle(color: Colors.cyanAccent, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: dsh.logs.length,
              itemBuilder: (context, i) {
                final log = dsh.logs[dsh.logs.length - 1 - i];
                return Text(
                  log,
                  style: GoogleFonts.jetBrainsMono(color: Colors.greenAccent, fontSize: 10.5),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showApiKeysDialog(BuildContext context, SettingsState settings) {
    final dsCtrl = TextEditingController(text: settings.deepseekApiKey);
    final orCtrl = TextEditingController(text: settings.openrouterApiKey);
    final oaCtrl = TextEditingController(text: settings.openaiApiKey);
    final anCtrl = TextEditingController(text: settings.anthropicApiKey);
    final portCtrl = TextEditingController(text: settings.dshPort.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.key, color: Colors.cyanAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              'API Ключи провайдеров',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ключи автоматически пробрасываются в окружение DeepSeek Harness:',
                style: TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              _buildField('DeepSeek API Key (DEEPSEEK_API_KEY)', dsCtrl),
              const SizedBox(height: 8),
              _buildField('OpenRouter Key (доступ ко всем моделям)', orCtrl),
              const SizedBox(height: 8),
              _buildField('OpenAI Key (OPENAI_API_KEY)', oaCtrl),
              const SizedBox(height: 8),
              _buildField('Anthropic Key (ANTHROPIC_API_KEY)', anCtrl),
              const SizedBox(height: 8),
              _buildField('Порт сервера (по умолчанию 3080)', portCtrl, isNumber: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
            onPressed: () {
              final sn = ref.read(settingsProvider.notifier);
              sn.setDeepseekApiKey(dsCtrl.text.trim());
              sn.setOpenrouterApiKey(orCtrl.text.trim());
              sn.setOpenaiApiKey(oaCtrl.text.trim());
              sn.setAnthropicApiKey(anCtrl.text.trim());
              final p = int.tryParse(portCtrl.text.trim()) ?? 3080;
              sn.setDshPort(p);
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 3),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            obscureText: !isNumber,
            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          ),
        ),
      ],
    );
  }
}
