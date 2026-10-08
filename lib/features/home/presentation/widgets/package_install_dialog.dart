import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/models/optional_package.dart';

class PackageInstallDialog extends ConsumerStatefulWidget {
  final OptionalPackage package;
  final bool isUpdate;

  const PackageInstallDialog({
    super.key,
    required this.package,
    this.isUpdate = false,
  });

  static Future<void> show(BuildContext context, OptionalPackage package, {bool isUpdate = false}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PackageInstallDialog(package: package, isUpdate: isUpdate),
    );
  }

  @override
  ConsumerState<PackageInstallDialog> createState() => _PackageInstallDialogState();
}

class _PackageInstallDialogState extends ConsumerState<PackageInstallDialog> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  Process? _process;
  StreamingCommand? _streamingCommand;
  bool _isRunning = true;
  bool _isSuccess = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startProcess();
  }

  @override
  void dispose() {
    _process?.kill(ProcessSignal.sigkill);
    _streamingCommand?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isNoisyLog(String text) {
    final lower = text.toLowerCase();
    if (lower.contains("proot warning: can't sanitize binding")) return true;
    if (lower.contains('apt does not have a stable cli interface')) return true;
    if (lower.contains('debconf: delaying package configuration')) return true;
    if (lower.contains('/proc/self/fd/')) return true;
    if (lower.contains('scanning processes')) return true;
    return false;
  }

  bool _isHarmlessInfo(String text) {
    final lower = text.toLowerCase();
    return lower.contains('get:') ||
        lower.contains('hit:') ||
        lower.contains('unpacking') ||
        lower.contains('setting up') ||
        lower.contains('selecting previously') ||
        lower.contains('progress:');
  }

  static final _ansiRegex = RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07|[()][A-Za-z0-9])');
  String _cleanAnsi(String text) => text.replaceAll(_ansiRegex, '');

  Future<void> _startProcess() async {
    setState(() {
      _isRunning = true;
      _isSuccess = false;
      _errorMessage = null;
      _logs.clear();
      _logs.add('🚀 [QuantumIDE] Запуск установки: ${widget.package.name}...');
      if (widget.isUpdate) {
        _logs.add('🔄 Режим: Обновление / переустановка пакета');
      }
    });

    final runtime = ref.read(runtimeServiceProvider);
    String command = widget.package.command;

    if (widget.isUpdate) {
      if (widget.package.id == 'antigravity-cli') {
        command = 'agy update || (ARCH=\$(uname -m) && if [ "\$ARCH" = "aarch64" ] || [ "\$ARCH" = "arm64" ]; then URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-arm/cli_linux_arm64.tar.gz"; else URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-x64/cli_linux_x64.tar.gz"; fi && mkdir -p /tmp/agy_dl && (curl -k -fL --retry 3 "\$URL" || wget --no-check-certificate -qO- "\$URL") | tar -xz -C /tmp/agy_dl && mkdir -p /usr/local/bin && mv /tmp/agy_dl/antigravity /usr/local/bin/agy && ln -sf /usr/local/bin/agy /usr/local/bin/antigravity && chmod +x /usr/local/bin/agy && rm -rf /tmp/agy_dl && echo "Antigravity CLI updated successfully")';
      } else if (widget.package.id == 'claude-code') {
        command = 'npm install -g @anthropic-ai/claude-code@latest';
      } else if (widget.package.id == 'deepseek-harness') {
        command = 'npm install -g @deepseek-ai/dsh@latest';
      } else if (widget.package.id == 'kilocode-cli') {
        command = 'npm install -g @kilocode/cli@latest';
      } else if (widget.package.id == 'opencode-ai') {
        command = 'npm install -g opencode-ai@latest';
      } else if (widget.package.id == 'flutter') {
        command = 'if [ -d /root/flutter/.git ]; then cd /root/flutter && git pull && /root/flutter/bin/flutter precache; else ${widget.package.command}; fi';
      } else if (widget.package.id == 'python') {
        command = 'export HOME=/root ; export USER=root ; apt update && apt install --reinstall -y python3 python3-pip python-is-python3';
      } else if (widget.package.id == 'git') {
        command = 'export HOME=/root ; export USER=root ; apt update && apt install --reinstall -y git ca-certificates';
      } else if (widget.package.id == 'nodejs') {
        command = 'export HOME=/root ; export USER=root ; curl -4 -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y --reinstall nodejs';
      } else if (widget.package.id == 'build-essential') {
        command = 'export HOME=/root ; export USER=root ; apt update && apt install --reinstall -y build-essential';
      } else {
        // Run full package command for SDK components, LSPs, etc.
        command = widget.package.command;
      }
    } else if (widget.package.id == 'antigravity-cli' && !Platform.isAndroid && !Platform.isIOS) {
      command = 'mkdir -p ~/.local/bin && curl -fL --retry 3 "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-x64/cli_linux_x64.tar.gz" | tar -xz -C /tmp antigravity && mv /tmp/antigravity ~/.local/bin/agy && chmod +x ~/.local/bin/agy && agy --version';
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        _logs.add('📦 Окружение: Android PRoot userspace');
        _logs.add('\$ $command\n');

        _streamingCommand = runtime.runCommandStream(
          command,
          onLine: (line, {bool isError = false, bool replace = false}) {
            if (mounted) {
              final cleaned = _cleanAnsi(line);
              if (cleaned.trim().isNotEmpty && !_isNoisyLog(cleaned)) {
                final markAsError = isError && !_isHarmlessInfo(cleaned);
                setState(() {
                  if (replace && _logs.isNotEmpty) {
                    _logs[_logs.length - 1] = markAsError ? '⚠️ $cleaned' : cleaned;
                  } else {
                    _logs.add(markAsError ? '⚠️ $cleaned' : cleaned);
                  }
                });
                _scrollToBottom();
              }
            }
          },
        );

        final exitCode = await _streamingCommand!.exitCode;
        _streamingCommand = null;

        if (mounted) {
          setState(() {
            _isRunning = false;
            if (exitCode == 0) {
              _isSuccess = true;
              _logs.add('✨ [QuantumIDE] Пакет ${widget.package.name} успешно установлен!');
            } else {
              _isSuccess = false;
              _errorMessage = 'Процесс завершился с кодом $exitCode';
              _logs.add('❌ Ошибка: $_errorMessage');
            }
          });
          _scrollToBottom();

          if (_isSuccess) {
            await ref.read(packageServiceProvider.notifier).checkActualInstallation();
          }
        }
      } else {
        // Desktop Linux/macOS/Windows
        _logs.add('💻 Окружение: Нативная система (${Platform.operatingSystem})');
        
        // Adapt command for PC if needed
        String desktopCmd = command;
        final isRoot = (Platform.environment['USER'] == 'root') || (Platform.environment['HOME'] == '/root');

        if (widget.package.id == 'claude-code') {
          desktopCmd = widget.isUpdate
              ? 'npm update -g @anthropic-ai/claude-code'
              : 'npm install -g @anthropic-ai/claude-code';
        } else if (widget.package.id == 'deepseek-harness') {
          desktopCmd = 'npm install -g @deepseek-ai/dsh@latest && (if [ ! -f /usr/local/bin/dsh ]; then printf "#!/bin/sh\\nexec node /usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh/lib/bin.js \\"\$@\\"\\n" > /usr/local/bin/dsh && chmod +x /usr/local/bin/dsh; fi)';
        } else if (widget.package.id == 'antigravity-cli') {
          final isArm = Platform.version.toLowerCase().contains('arm') || Platform.version.toLowerCase().contains('aarch64');
          final url = isArm
              ? 'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-arm/cli_linux_arm64.tar.gz'
              : 'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-x64/cli_linux_x64.tar.gz';
          desktopCmd = 'mkdir -p ~/.local/bin /tmp/agy_dl && curl -fL --retry 3 "$url" | tar -xz -C /tmp/agy_dl && (mv /tmp/agy_dl/antigravity ~/.local/bin/agy 2>/dev/null || mv /tmp/agy_dl/antigravity /usr/local/bin/agy 2>/dev/null || true) && (chmod +x ~/.local/bin/agy 2>/dev/null || true) && (chmod +x /usr/local/bin/agy 2>/dev/null || true) && rm -rf /tmp/agy_dl && agy --version';
        } else if (!isRoot && desktopCmd.contains('pgrep -x "apt|apt-get|dpkg|dpkg-deb"')) {
          final idx = desktopCmd.indexOf(' ; ');
          if (idx != -1 && idx + 3 < desktopCmd.length) {
            desktopCmd = desktopCmd.substring(idx + 3);
          }
          desktopCmd = desktopCmd.replaceAll('apt update', 'sudo apt update')
                                 .replaceAll('apt install', 'sudo apt install')
                                 .replaceAll('/root/', '~/');
        }

        final env = Map<String, String>.from(Platform.environment);
        final home = Platform.environment['HOME'] ?? '';
        final nvmBin = '$home/.config/nvm/versions/node/v22.18.0/bin';
        final localBin = '$home/.local/bin';
        env['PATH'] = '$localBin:$nvmBin:${env['PATH'] ?? ''}';

        _logs.add('\$ $desktopCmd\n');

        _process = await Process.start(
          'bash',
          ['-c', desktopCmd],
          environment: env,
        );

        _process!.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (mounted) {
            setState(() {
              _logs.add(_cleanAnsi(line));
            });
            _scrollToBottom();
          }
        });

        _process!.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (mounted) {
            setState(() {
              _logs.add('⚠️ ${_cleanAnsi(line)}');
            });
            _scrollToBottom();
          }
        });

        final exitCode = await _process!.exitCode;
        _process = null;

        if (mounted) {
          setState(() {
            _isRunning = false;
            if (exitCode == 0) {
              _isSuccess = true;
              _logs.add('✨ [QuantumIDE] Пакет ${widget.package.name} успешно установлен!');
            } else {
              _isSuccess = false;
              _errorMessage = 'Процесс завершился с кодом $exitCode';
              _logs.add('❌ Ошибка: $_errorMessage');
            }
          });
          _scrollToBottom();

          if (_isSuccess) {
            await ref.read(packageServiceProvider.notifier).checkActualInstallation();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _isSuccess = false;
          _errorMessage = e.toString();
          _logs.add('❌ Критическая ошибка выполнения: $e');
        });
        _scrollToBottom();
      }
    }
  }

  void _stopProcess() {
    _streamingCommand?.cancel();
    _streamingCommand = null;
    _process?.kill(ProcessSignal.sigterm);
    Future.delayed(const Duration(milliseconds: 300), () {
      _process?.kill(ProcessSignal.sigkill);
      _process = null;
    });
    setState(() {
      _isRunning = false;
      _logs.add('🛑 Установка прервана пользователем.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: isDesktop ? 680 : double.infinity,
        height: isDesktop ? 540 : size.height * 0.75,
        decoration: BoxDecoration(
          color: const Color(0xFF10141D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isRunning
                ? Colors.cyanAccent.withValues(alpha: 0.3)
                : (_isSuccess ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3)),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.package.icon, color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isUpdate ? 'Обновление: ${widget.package.name}' : 'Установка: ${widget.package.name}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.package.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  if (_isRunning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                          ),
                          const SizedBox(width: 8),
                          Text('Выполняется...', style: GoogleFonts.inter(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                  else if (_isSuccess)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.circle_check, size: 14, color: Colors.greenAccent),
                          const SizedBox(width: 6),
                          Text('Установлено', style: GoogleFonts.inter(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.circle_alert, size: 14, color: Colors.redAccent),
                          const SizedBox(width: 6),
                          Text('Ошибка', style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            if (_isRunning)
              const LinearProgressIndicator(
                backgroundColor: Color(0xFF161B26),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                minHeight: 2,
              ),

            // Console Log Box
            Expanded(
              child: Container(
                color: const Color(0xFF0D1017),
                padding: const EdgeInsets.all(16),
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final line = _logs[index];
                      Color color = Colors.white70;
                      if (line.startsWith('🚀') || line.startsWith('📦') || line.startsWith('💻')) {
                        color = Colors.cyanAccent;
                      } else if (line.startsWith('✨') || line.startsWith('✅')) {
                        color = Colors.greenAccent;
                      } else if (line.startsWith('❌') || line.startsWith('⚠️')) {
                        color = Colors.redAccent;
                      } else if (line.startsWith('\$')) {
                        color = Colors.amberAccent;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Text(
                          line,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            color: color,
                            height: 1.35,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Bottom Actions Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_isRunning)
                    TextButton.icon(
                      icon: const Icon(LucideIcons.square, size: 14, color: Colors.redAccent),
                      label: Text('Остановить', style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                      onPressed: _stopProcess,
                    )
                  else if (!_isSuccess)
                    TextButton.icon(
                      icon: const Icon(LucideIcons.rotate_ccw, size: 14, color: Colors.cyanAccent),
                      label: Text('Повторить', style: GoogleFonts.inter(fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.w600)),
                      onPressed: _startProcess,
                    )
                  else
                    const SizedBox.shrink(),

                  Row(
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSuccess ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.white12,
                          foregroundColor: _isSuccess ? Colors.greenAccent : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isRunning ? null : () => Navigator.pop(context),
                        child: Text(
                          _isSuccess ? 'Готово' : 'Закрыть',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
