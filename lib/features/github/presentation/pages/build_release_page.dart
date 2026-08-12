import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/github_service.dart';

/// Экран «Сборка и публикация»: вставляете GitHub-токен, версию и заметки —
/// приложение само коммитит новую версию в pubspec, запускает GitHub Actions
/// и показывает прогресс сборки и ссылку на релиз.
class BuildReleasePage extends StatefulWidget {
  const BuildReleasePage({super.key});

  @override
  State<BuildReleasePage> createState() => _BuildReleasePageState();
}

class _BuildReleasePageState extends State<BuildReleasePage> {
  final _github = GitHubService();
  final _tokenCtrl = TextEditingController();
  final _repoCtrl = TextEditingController(text: 'Lesorub361/quantum_ide');
  final _versionCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _working = false;
  String _status = '';
  String? _releaseUrl;
  String? _runUrl;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    if (_github.isAuthenticated) {
      final v = await _github.getCurrentVersion('Lesorub361', 'quantum_ide');
      if (v != null && mounted) setState(() => _versionCtrl.text = _bumpPatch(v));
    }
  }

  String _bumpPatch(String v) {
    final parts = v.split('.');
    if (parts.length != 3) return v;
    final patch = int.tryParse(parts[2]) ?? 0;
    return '${parts[0]}.${parts[1]}.${patch + 1}';
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _repoCtrl.dispose();
    _versionCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    setState(() {
      _working = true;
      _status = '';
      _releaseUrl = null;
      _runUrl = null;
    });

    try {
      if (!_github.isAuthenticated) {
        final token = _tokenCtrl.text.trim();
        if (token.isEmpty) {
          _setStatus('❌ Введите GitHub-токен (с правами repo + workflow).');
          return;
        }
        await _github.authenticateWithToken(token);
      }

      final repoParts = _repoCtrl.text.trim().split('/');
      if (repoParts.length != 2) {
        _setStatus('❌ Репозиторий укажите как owner/repo.');
        return;
      }
      final owner = repoParts[0];
      final repo = repoParts[1];
      final version = _versionCtrl.text.trim();
      if (version.isEmpty) {
        _setStatus('❌ Укажите версию (например, 1.1.6).');
        return;
      }

      // 1) Обновляем версию в pubspec.yaml через Contents API
      _setStatus('⏳ Обновляю версию в pubspec.yaml → $version…');
      final file = await _github.getFile(owner, repo, 'pubspec.yaml');
      if (file == null) {
        _setStatus('❌ Не удалось прочитать pubspec.yaml (проверьте доступ к репозиторию).');
        return;
      }
      final newContent = file.content.replaceAllMapped(
        RegExp(r'^version:\s*[\d.]+\+\d*', multiLine: true),
        (m) => 'version: $version+${_nextBuild(file.content)}',
      );
      final ok = await _github.updateFile(
        owner,
        repo,
        'pubspec.yaml',
        newContent,
        'v$version',
        file.sha,
      );
      if (!ok) {
        _setStatus('❌ Не удалось закоммитить pubspec.yaml.');
        return;
      }

      // 2) Запускаем workflow сборки/публикации
      _setStatus('⏳ Запускаю сборку GitHub Actions (v$version)…');
      final triggered = await _github.triggerWorkflow(
        owner: owner,
        repo: repo,
        version: version,
        notes: _notesCtrl.text.trim(),
      );
      if (!triggered) {
        _setStatus('❌ Не удалось запустить workflow. Проверьте права токена (workflow).');
        return;
      }

      // 3) Опрашиваем статус сборки
      for (int i = 0; i < 45; i++) {
        await Future.delayed(const Duration(seconds: 8));
        final runs = await _github.listWorkflowRuns(owner, repo, limit: 3);
        if (runs.isEmpty) continue;
        final run = runs.first;
        _runUrl = run['html_url'] as String?;
        final status = run['status'] as String? ?? '';
        final conclusion = run['conclusion'] as String?;
        _setStatus('⏳ Сборка: $status${conclusion != null ? ' ($conclusion)' : ''}… попытка ${i + 1}/45');
        if (conclusion == 'success') {
          // 4) Берём свежий релиз
          final rel = await _github.getLatestRelease(owner, repo);
          final tag = rel?['tag_name'] as String?;
          if (tag == version || rel != null) {
            setState(() => _releaseUrl = rel?['html_url'] as String?);
          }
          _setStatus('✅ Готово! Релиз v$version опубликован.');
          return;
        } else if (conclusion == 'failure' || conclusion == 'cancelled') {
          _setStatus('❌ Сборка завершилась: $conclusion. Подробнее: $_runUrl');
          return;
        }
      }
      _setStatus('⏳ Сборка ещё идёт. Проверьте статус: $_runUrl');
    } catch (e) {
      _setStatus('❌ Ошибка: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  int _nextBuild(String content) {
    final m = RegExp(r'^version:\s*[\d.]+?\+(\d+)', multiLine: true).firstMatch(content);
    final cur = int.tryParse(m?.group(1) ?? '0') ?? 0;
    return cur + 1;
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181D),
        title: Text('Сборка и публикация',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_github.isAuthenticated)
              _field('GitHub токен (ghp_…)', _tokenCtrl, hint: 'нужны права repo + workflow', obscure: true),
            if (_github.isAuthenticated)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('✅ Уже авторизован через сохранённый токен.',
                    style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 12)),
              ),
            _field('Репозиторий (owner/repo)', _repoCtrl, hint: 'Lesorub361/quantum_ide'),
            const SizedBox(height: 12),
            _field('Версия', _versionCtrl, hint: '1.1.6'),
            const SizedBox(height: 12),
            Text('Заметки к релизу', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesCtrl,
              maxLines: 6,
              decoration: _inputDeco('Что нового в этой версии…'),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _working ? null : _publish,
                icon: _working
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.rocket, size: 16),
                label: Text(_working ? 'Публикуем…' : 'Собрать и опубликовать'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: SelectableText(_status, style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, height: 1.4)),
              ),
            if (_releaseUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText('Релиз: $_releaseUrl',
                    style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 12)),
              ),
            if (_runUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText('Сборка: $_runUrl',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          obscureText: obscure,
          decoration: _inputDeco(hint ?? ''),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.25),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
}
