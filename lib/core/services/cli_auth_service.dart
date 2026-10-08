import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

enum AntigravityAuthStatus {
  signedOut,
  starting,
  awaitingCode,
  completing,
  signedIn,
  error,
}

class CliAuthState {
  final AntigravityAuthStatus antigravityStatus;
  final String? googleAccountEmail;
  final String? antigravityAuthUrl;
  final String? antigravityMessage;
  final String antigravityEffort; // 'low', 'medium', 'high'
  final List<String> antigravityModels;
  final bool isAntigravityModelsLoading;
  final bool isGoogleAuthenticated;

  final String? geminiApiKey;
  final String? anthropicApiKey;
  final bool isClaudeAuthenticated;
  final String? deepseekApiKey;
  final String? openRouterApiKey;
  final String deepseekProviderType; // 'deepseek', 'openrouter', 'anthropic', 'kimi', 'opencode_zen', 'nvidia', 'custom'
  final String claudeProviderType; // 'anthropic', 'openrouter', 'claude_subscription'

  const CliAuthState({
    this.antigravityStatus = AntigravityAuthStatus.signedOut,
    this.googleAccountEmail,
    this.antigravityAuthUrl,
    this.antigravityMessage,
    this.antigravityEffort = 'medium',
    this.antigravityModels = const [
      'gemini-3.8-flash-high',
      'gemini-3.8-flash-medium',
      'gemini-3.8-flash-low',
      'gemini-3.7-flash-high',
      'gemini-3.7-flash-medium',
      'gemini-3.7-flash-low',
      'gemini-3.6-flash-high',
      'gemini-3.6-flash-medium',
      'gemini-3.6-flash-low',
      'gemini-3.1-pro-high',
      'gemini-3.1-pro-low',
      'claude-sonnet-4-6',
      'claude-opus-4-6-thinking',
      'gpt-oss-120b-medium',
    ],
    this.isAntigravityModelsLoading = false,
    this.isGoogleAuthenticated = false,
    this.geminiApiKey,
    this.anthropicApiKey,
    this.isClaudeAuthenticated = false,
    this.deepseekApiKey,
    this.openRouterApiKey,
    this.deepseekProviderType = 'deepseek',
    this.claudeProviderType = 'anthropic',
  });

  CliAuthState copyWith({
    AntigravityAuthStatus? antigravityStatus,
    String? googleAccountEmail,
    bool clearEmail = false,
    String? antigravityAuthUrl,
    String? antigravityMessage,
    String? antigravityEffort,
    List<String>? antigravityModels,
    bool? isAntigravityModelsLoading,
    bool? isGoogleAuthenticated,
    String? geminiApiKey,
    String? anthropicApiKey,
    bool? isClaudeAuthenticated,
    String? deepseekApiKey,
    String? openRouterApiKey,
    String? deepseekProviderType,
    String? claudeProviderType,
  }) {
    return CliAuthState(
      antigravityStatus: antigravityStatus ?? this.antigravityStatus,
      googleAccountEmail: clearEmail ? null : (googleAccountEmail ?? this.googleAccountEmail),
      antigravityAuthUrl: antigravityAuthUrl ?? this.antigravityAuthUrl,
      antigravityMessage: antigravityMessage ?? this.antigravityMessage,
      antigravityEffort: antigravityEffort ?? this.antigravityEffort,
      antigravityModels: antigravityModels ?? this.antigravityModels,
      isAntigravityModelsLoading: isAntigravityModelsLoading ?? this.isAntigravityModelsLoading,
      isGoogleAuthenticated: isGoogleAuthenticated ?? this.isGoogleAuthenticated,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
      isClaudeAuthenticated: isClaudeAuthenticated ?? this.isClaudeAuthenticated,
      deepseekApiKey: deepseekApiKey ?? this.deepseekApiKey,
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      deepseekProviderType: deepseekProviderType ?? this.deepseekProviderType,
      claudeProviderType: claudeProviderType ?? this.claudeProviderType,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE-HARNESS PARSING & TUI HELPERS
// ─────────────────────────────────────────────────────────────────────────────

const String _terminalHandshakeReply = "\x1B[?2026;1\$y\x1B[?2027;1\$y\x1B[?1u\n";
final RegExp _authAnsi = RegExp(r'\x1B(?:\][^\x07]*(?:\x07|\x1B\\)|\[[0-?]*[ -/]*[@-~]|[()][A-Z0-9])');
final RegExp _googleOAuthUrlRegex = RegExp(r'''https://accounts\.google\.com/[^\s"'<>]*?[?&]state=[A-Za-z0-9._~-]+''');
final RegExp _emailRegex = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', caseSensitive: false);

String _sanitizeTerminalOutput(String text) {
  return text.replaceAll(_authAnsi, '').split('').where((ch) {
    final code = ch.codeUnitAt(0);
    return ch == '\n' || ch == '\r' || ch == '\t' || code >= 0x20;
  }).join();
}

String? _extractGoogleOAuthUrl(String output) {
  final compact = output.replaceAll(RegExp(r'[\r\n\t ]+'), '');
  final match = _googleOAuthUrlRegex.firstMatch(compact);
  if (match != null && match.group(0)!.contains('client_id=') && match.group(0)!.contains('code_challenge=')) {
    return match.group(0);
  }
  if (!output.toLowerCase().contains('select login method') &&
      (output.toLowerCase().contains('browser') || output.toLowerCase().contains('visit') ||
       output.toLowerCase().contains('open') || output.toLowerCase().contains('code') ||
       output.toLowerCase().contains('paste'))) {
    final candidates = RegExp(r'''https://[^\s"'<>]{20,}''')
        .allMatches(compact)
        .map((m) => m.group(0)!)
        .where((u) => u.length >= 30 && u.contains('.'))
        .toList();
    for (final c in candidates) {
      if (c.contains('google')) return c;
    }
    if (candidates.isNotEmpty) return candidates.first;
  }
  return null;
}

bool _isSignedInScreen(String output) {
  final lower = output.toLowerCase();
  return lower.contains('for shortcuts') || (lower.contains('antigravity cli') && lower.contains('google ai'));
}

String? _extractSignedInEmail(String output) {
  final matches = _emailRegex.allMatches(output);
  for (final m in matches) {
    final email = m.group(0)!;
    if (!email.toLowerCase().endsWith('.apps.googleusercontent.com')) {
      return email;
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI AUTH NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class CliAuthNotifier extends StateNotifier<CliAuthState> {
  Process? _authProcess;
  StreamSubscription? _authStdoutSub;
  StreamSubscription? _authStderrSub;
  Timer? _authPollTimer;

  int _handshakeReplies = 0;
  int _lastHandshakeLength = 0;
  bool _loginMenuAdvanced = false;
  bool _colorScreenCompleted = false;
  bool _renderingScreenCompleted = false;
  bool _privacyScreenCompleted = false;
  bool _workspaceTrustCompleted = false;

  CliAuthNotifier() : super(const CliAuthState()) {
    loadAuthInfo();
  }

  String get _homeDir => Platform.environment['HOME'] ?? '';

  File get _officialCredentialFile =>
      File(p.join(_homeDir, '.gemini', 'antigravity-cli', 'antigravity-oauth-token'));

  bool hasOfficialCredential() {
    if (_officialCredentialFile.existsSync()) return true;
    final oauthCredsFile = File(p.join(_homeDir, '.gemini', 'oauth_creds.json'));
    if (oauthCredsFile.existsSync()) return true;
    final googleAccountsFile = File(p.join(_homeDir, '.gemini', 'google_accounts.json'));
    if (googleAccountsFile.existsSync()) {
      try {
        final content = googleAccountsFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final active = json['active'] as String?;
        if (active != null && active.trim().isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> loadAuthInfo() async {
    final prefs = await SharedPreferences.getInstance();

    final savedEmail = prefs.getString('cli_google_email');
    bool isGoogleAuth = prefs.getBool('cli_google_auth') ?? false;

    // Detect existing system Antigravity authentication (Desktop & PRoot)
    String? detectedEmail = savedEmail;
    final googleAccountsFile = File(p.join(_homeDir, '.gemini', 'google_accounts.json'));
    final oauthCredsFile = File(p.join(_homeDir, '.gemini', 'oauth_creds.json'));

    if (googleAccountsFile.existsSync()) {
      try {
        final content = googleAccountsFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final active = json['active'] as String?;
        if (active != null && active.trim().isNotEmpty) {
          detectedEmail = active.trim();
          isGoogleAuth = true;
          await prefs.setBool('cli_google_auth', true);
          await prefs.setString('cli_google_email', detectedEmail);
        }
      } catch (_) {}
    }

    if (!isGoogleAuth && (hasOfficialCredential() || oauthCredsFile.existsSync())) {
      isGoogleAuth = true;
      detectedEmail ??= 'Google Account';
      await prefs.setString('cli_google_email', detectedEmail);
    }

    // Read API keys
    final geminiKey = prefs.getString('cli_gemini_api_key') ?? Platform.environment['GEMINI_API_KEY'];
    final anthropicKey = prefs.getString('cli_anthropic_api_key') ?? Platform.environment['ANTHROPIC_API_KEY'];
    final deepseekKey = prefs.getString('cli_deepseek_api_key') ?? Platform.environment['DEEPSEEK_API_KEY'];
    final openrouterKey = prefs.getString('cli_openrouter_api_key') ?? Platform.environment['OPENROUTER_API_KEY'];
    final dsProviderType = prefs.getString('cli_deepseek_provider') ?? 'deepseek';
    final claudeProviderType = prefs.getString('cli_claude_provider') ?? 'anthropic';
    final effort = prefs.getString('cli_antigravity_effort') ?? 'medium';

    final isAntigravityActive = isGoogleAuth || (geminiKey != null && geminiKey.isNotEmpty);

    state = state.copyWith(
      googleAccountEmail: (isGoogleAuth && detectedEmail != null && detectedEmail.isNotEmpty) ? detectedEmail : null,
      isGoogleAuthenticated: isGoogleAuth,
      antigravityStatus: isAntigravityActive ? AntigravityAuthStatus.signedIn : AntigravityAuthStatus.signedOut,
      antigravityMessage: isGoogleAuth
          ? 'Подключено через Google (${detectedEmail ?? "Google Account"})'
          : (geminiKey != null && geminiKey.isNotEmpty ? 'Подключено через Gemini API Key' : null),
      antigravityEffort: effort,
      geminiApiKey: geminiKey,
      anthropicApiKey: anthropicKey,
      isClaudeAuthenticated: (anthropicKey != null && anthropicKey.isNotEmpty) ||
          (claudeProviderType == 'openrouter' && openrouterKey != null && openrouterKey.isNotEmpty),
      deepseekApiKey: deepseekKey,
      openRouterApiKey: openrouterKey,
      deepseekProviderType: dsProviderType,
      claudeProviderType: claudeProviderType,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANTIGRAVITY AUTHENTICATION (Mobile-Harness AntigravityAuthController)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> startAntigravityLogin() async {
    _cancelAuthProcess();

    _handshakeReplies = 0;
    _lastHandshakeLength = 0;
    _loginMenuAdvanced = false;
    _colorScreenCompleted = false;
    _renderingScreenCompleted = false;
    _privacyScreenCompleted = false;
    _workspaceTrustCompleted = false;

    // First check if already authorized in system
    final googleAccountsFile = File(p.join(_homeDir, '.gemini', 'google_accounts.json'));
    if (googleAccountsFile.existsSync()) {
      try {
        final content = googleAccountsFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final active = json['active'] as String?;
        if (active != null && active.trim().isNotEmpty) {
          await _completeSuccessfulAuth(active.trim());
          return;
        }
      } catch (_) {}
    }

    state = state.copyWith(
      antigravityStatus: AntigravityAuthStatus.starting,
      antigravityMessage: 'Запуск мастера входа Antigravity CLI...',
      antigravityAuthUrl: null,
    );

    try {
      final candidates = [
        p.join(_homeDir, '.local', 'bin', 'agy'),
        '/usr/local/bin/agy',
        '/usr/bin/agy',
        'agy',
        'antigravity',
      ];

      String? agyPath;
      for (final c in candidates) {
        if (c.contains('/') && File(c).existsSync()) {
          agyPath = c;
          break;
        }
      }
      agyPath ??= 'agy';

      // On Linux/Desktop: try launching interactive desktop terminal where browser OAuth works natively
      bool launchedDesktopTerminal = false;
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        final termCmds = [
          ['deepin-terminal', '-e', agyPath],
          ['x-terminal-emulator', '-e', agyPath],
          ['gnome-terminal', '--', agyPath],
          ['xterm', '-e', agyPath],
          ['konsole', '-e', agyPath],
        ];

        for (final cmd in termCmds) {
          try {
            final check = await Process.run('which', [cmd[0]]);
            if (check.exitCode == 0) {
              await Process.start(cmd[0], cmd.sublist(1));
              launchedDesktopTerminal = true;
              break;
            }
          } catch (_) {}
        }
      }

      if (launchedDesktopTerminal) {
        state = state.copyWith(
          antigravityStatus: AntigravityAuthStatus.starting,
          antigravityMessage: 'Открыт терминал авторизации. Войдите в Google в окне браузера. Статус обновится автоматически...',
        );

        _startGoogleAccountsPolling();
        return;
      }

      // Fallback: Headless interactive flow with SSH_CONNECTION (for Android / PRoot / remote headless)
      final env = Map<String, String>.from(Platform.environment);
      env['SSH_CONNECTION'] = '127.0.0.1 1 127.0.0.1 1';
      env['TERM'] = 'xterm-256color';
      env['NO_COLOR'] = '1';

      _authProcess = await Process.start(
        agyPath,
        [],
        environment: env,
      );

      final outputBuffer = StringBuffer();

      void handleTerminalChunk(String chunk) {
        outputBuffer.write(chunk);
        final rawText = outputBuffer.toString();
        final cleanText = _sanitizeTerminalOutput(rawText);

        // 1. Terminal handshake response (DEC mode / Kitty query from Ink TUI)
        if (_handshakeReplies < 5 &&
            rawText.length - _lastHandshakeLength > 100 &&
            rawText.substring(_lastHandshakeLength).contains("\x1B[?u")) {
          _sendToProcess(_terminalHandshakeReply);
          _handshakeReplies++;
          _lastHandshakeLength = rawText.length;
        }

        // 2. Select login method: 1. Google OAuth (send Enter CR+LF)
        if (!_loginMenuAdvanced &&
            cleanText.toLowerCase().contains("select login method") &&
            cleanText.toLowerCase().contains("google oauth")) {
          _sendToProcess("\r\n");
          _loginMenuAdvanced = true;
          state = state.copyWith(
            antigravityMessage: 'Google OAuth выбран — генерация ссылки для браузера...',
          );
        }

        // 3. Extract Google OAuth URL
        final url = _extractGoogleOAuthUrl(cleanText);
        if (url != null && state.antigravityAuthUrl == null) {
          state = state.copyWith(
            antigravityStatus: AntigravityAuthStatus.awaitingCode,
            antigravityAuthUrl: url,
            antigravityMessage: 'Завершите вход в Google в браузере и вставьте полученный код.',
          );
        }

        // 4. Color scheme prompt
        if (!_colorScreenCompleted && cleanText.toLowerCase().contains("choose your color scheme")) {
          _sendToProcess("\r\n");
          _colorScreenCompleted = true;
        }

        // 5. Rendering mode prompt (select inline mode for captured terminal)
        if (!_renderingScreenCompleted &&
            cleanText.toLowerCase().contains("no flickering") &&
            cleanText.toLowerCase().contains("native terminal experience (inline)")) {
          _sendToProcess("\x1B[B\r\n"); // Down arrow + Enter
          _renderingScreenCompleted = true;
        }

        // 6. Privacy & Terms screen (space to opt out, tab, tab, enter)
        if (!_privacyScreenCompleted &&
            cleanText.toLowerCase().contains("terms of service & data use") &&
            cleanText.toLowerCase().contains("help improve antigravity cli")) {
          final optOut = cleanText.toLowerCase().contains("[x] yes") ? " \t\t\r\n" : "\t\t\r\n";
          _sendToProcess(optOut);
          _privacyScreenCompleted = true;
          state = state.copyWith(
            antigravityMessage: 'Подтверждение приватности и завершение настройки...',
          );
        }

        // 7. Workspace trust
        if (!_workspaceTrustCompleted &&
            cleanText.toLowerCase().contains("do you trust the contents of this project")) {
          _sendToProcess("\r\n");
          _workspaceTrustCompleted = true;
        }

        // 8. Successful sign in detection
        if (_isSignedInScreen(cleanText)) {
          final email = _extractSignedInEmail(cleanText) ?? 'Google Account';
          _completeSuccessfulAuth(email);
          _sendToProcess("/quit\r\n");
        }

        // 9. Failure detection
        if (cleanText.toLowerCase().contains("authentication failed") ||
            cleanText.toLowerCase().contains("failed to exchange")) {
          state = state.copyWith(
            antigravityStatus: AntigravityAuthStatus.error,
            antigravityMessage: 'Ошибка аутентификации Google. Попробуйте снова или используйте Gemini API Key.',
          );
          _cancelAuthProcess();
        }
      }

      _authStdoutSub = _authProcess!.stdout.transform(utf8.decoder).listen(handleTerminalChunk);
      _authStderrSub = _authProcess!.stderr.transform(utf8.decoder).listen(handleTerminalChunk);

      _authProcess!.exitCode.then((code) {
        if (state.antigravityStatus == AntigravityAuthStatus.starting ||
            state.antigravityStatus == AntigravityAuthStatus.completing) {
          if (hasOfficialCredential()) {
            _completeSuccessfulAuth(state.googleAccountEmail ?? 'Google Account');
          }
        }
      });
    } catch (e) {
      debugPrint('[CliAuthNotifier] Start error: $e');
      state = state.copyWith(
        antigravityStatus: AntigravityAuthStatus.error,
        antigravityMessage: 'Не удалось запустить Antigravity CLI: $e. Вы можете установить CLI во вкладке Настройки или указать Gemini API Key.',
      );
    }
  }

  void _startGoogleAccountsPolling() {
    _authPollTimer?.cancel();
    _authPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final googleAccountsFile = File(p.join(_homeDir, '.gemini', 'google_accounts.json'));
      if (googleAccountsFile.existsSync()) {
        try {
          final content = await googleAccountsFile.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final active = json['active'] as String?;
          if (active != null && active.trim().isNotEmpty) {
            timer.cancel();
            await _completeSuccessfulAuth(active.trim());
          }
        } catch (_) {}
      }
      if (timer.tick > 120) {
        timer.cancel();
        if (state.antigravityStatus == AntigravityAuthStatus.starting) {
          state = state.copyWith(
            antigravityStatus: AntigravityAuthStatus.error,
            antigravityMessage: 'Время ожидания авторизации истекло. Попробуйте снова.',
          );
        }
      }
    });
  }

  Future<void> launchInteractiveTerminal() async {
    final candidates = [
      p.join(_homeDir, '.local', 'bin', 'agy'),
      '/usr/local/bin/agy',
      '/usr/bin/agy',
      'agy',
    ];
    String agyPath = 'agy';
    for (final c in candidates) {
      if (File(c).existsSync()) {
        agyPath = c;
        break;
      }
    }

    final termCmds = [
      ['deepin-terminal', '-e', agyPath],
      ['x-terminal-emulator', '-e', agyPath],
      ['gnome-terminal', '--', agyPath],
      ['xterm', '-e', agyPath],
      ['konsole', '-e', agyPath],
    ];

    for (final cmd in termCmds) {
      try {
        final check = await Process.run('which', [cmd[0]]);
        if (check.exitCode == 0) {
          await Process.start(cmd[0], cmd.sublist(1));
          _startGoogleAccountsPolling();
          return;
        }
      } catch (_) {}
    }
  }

  void _sendToProcess(String input) {
    try {
      _authProcess?.stdin.write(input);
      _authProcess?.stdin.flush();
    } catch (_) {}
  }

  Future<void> submitAntigravityCode(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return;

    state = state.copyWith(
      antigravityStatus: AntigravityAuthStatus.completing,
      antigravityMessage: 'Передача кода подтверждения в Antigravity CLI...',
    );

    try {
      // In Ink raw terminal mode, CR+LF is treated as Enter key
      _sendToProcess('$cleanCode\r\n');

      String email = 'Google Account';
      if (cleanCode.contains('@')) {
        email = cleanCode;
      }

      await Future.delayed(const Duration(milliseconds: 1500));
      if (hasOfficialCredential()) {
        await _completeSuccessfulAuth(email);
      } else {
        final googleAccountsFile = File(p.join(_homeDir, '.gemini', 'google_accounts.json'));
        if (googleAccountsFile.existsSync()) {
          try {
            final content = googleAccountsFile.readAsStringSync();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final active = json['active'] as String?;
            if (active != null && active.trim().isNotEmpty) {
              email = active.trim();
            }
          } catch (_) {}
        }
        await _completeSuccessfulAuth(email);
      }
    } catch (e) {
      state = state.copyWith(
        antigravityStatus: AntigravityAuthStatus.error,
        antigravityMessage: 'Ошибка при отправке кода: $e',
      );
    }
  }

  Future<void> _completeSuccessfulAuth(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_google_email', email);
    await prefs.setBool('cli_google_auth', true);

    state = state.copyWith(
      antigravityStatus: AntigravityAuthStatus.signedIn,
      googleAccountEmail: email,
      isGoogleAuthenticated: true,
      antigravityMessage: 'Подключено как $email',
      antigravityAuthUrl: null,
    );
    _cancelAuthProcess();
  }

  Future<void> logoutAntigravity() async {
    _cancelAuthProcess();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cli_google_email');
    await prefs.setBool('cli_google_auth', false);

    // Delete official credential token file if any
    try {
      if (_officialCredentialFile.existsSync()) {
        await _officialCredentialFile.delete();
      }
      final altFile = File(p.join(_homeDir, '.gemini', 'oauth_creds.json'));
      if (altFile.existsSync()) {
        await altFile.delete();
      }
    } catch (_) {}

    state = state.copyWith(
      antigravityStatus: AntigravityAuthStatus.signedOut,
      clearEmail: true,
      isGoogleAuthenticated: false,
      antigravityMessage: 'Вы вышли из Google аккаунта',
      antigravityAuthUrl: null,
    );
  }

  void _cancelAuthProcess() {
    _authPollTimer?.cancel();
    _authPollTimer = null;
    try {
      _sendToProcess("/quit\r\n");
      _authProcess?.kill(ProcessSignal.sigterm);
      _authStdoutSub?.cancel();
      _authStderrSub?.cancel();
    } catch (_) {}
    _authProcess = null;
    _authStdoutSub = null;
    _authStderrSub = null;
  }

  Future<void> setAntigravityEffort(String effort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_antigravity_effort', effort);
    state = state.copyWith(antigravityEffort: effort);
  }

  Future<void> syncAntigravityModels() async {
    state = state.copyWith(isAntigravityModelsLoading: true);
    try {
      final candidates = [
        p.join(_homeDir, '.local', 'bin', 'agy'),
        '/usr/local/bin/agy',
        'agy',
      ];
      String agyPath = 'agy';
      for (final c in candidates) {
        if (File(c).existsSync()) {
          agyPath = c;
          break;
        }
      }

      final res = await Process.run(agyPath, ['models']);
      if (res.exitCode == 0 && res.stdout.toString().isNotEmpty) {
        final lines = res.stdout.toString().split('\n');
        final models = <String>[];
        for (final l in lines) {
          final trimmed = l.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          final first = parts.first;
          if (first.startsWith('gemini') || first.startsWith('claude') || first.startsWith('gpt')) {
            models.add(first);
          }
        }
        if (models.isNotEmpty) {
          state = state.copyWith(
            antigravityModels: models,
            isAntigravityModelsLoading: false,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('[CliAuthNotifier] Error syncing agy models: $e');
    }
    state = state.copyWith(isAntigravityModelsLoading: false);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CLAUDE & DEEPSEEK SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> setGeminiApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_gemini_api_key', key);
    state = state.copyWith(geminiApiKey: key);
    loadAuthInfo();
  }

  Future<void> setAnthropicApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_anthropic_api_key', key);
    state = state.copyWith(
      anthropicApiKey: key,
      isClaudeAuthenticated: key.isNotEmpty,
    );
  }

  Future<void> setClaudeProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_claude_provider', provider);
    state = state.copyWith(claudeProviderType: provider);
  }

  Future<void> setDeepSeekApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_deepseek_api_key', key);
    state = state.copyWith(deepseekApiKey: key);
  }

  Future<void> setOpenRouterApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_openrouter_api_key', key);
    state = state.copyWith(openRouterApiKey: key);
  }

  Future<void> setDeepSeekProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_deepseek_provider', provider);
    state = state.copyWith(deepseekProviderType: provider);
  }
}

final cliAuthProvider =
    StateNotifierProvider<CliAuthNotifier, CliAuthState>((ref) {
  return CliAuthNotifier();
});
