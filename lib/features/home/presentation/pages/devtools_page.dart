import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

class DevToolsPage extends StatefulWidget {
  const DevToolsPage({super.key});

  @override
  State<DevToolsPage> createState() => _DevToolsPageState();
}

class _DevToolsPageState extends State<DevToolsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1017),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141724),
        elevation: 0,
        title: Row(
          children: [
            const Icon(LucideIcons.wrench, color: Color(0xFF00E5FF), size: 20),
            const SizedBox(width: 10),
            Text(
              'DevTools Swiss Army Knife',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF00E5FF),
          indicatorWeight: 3,
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(LucideIcons.regex, size: 16), text: 'Regex Tester'),
            Tab(icon: Icon(LucideIcons.file_code, size: 16), text: 'JSON / Formatter'),
            Tab(icon: Icon(LucideIcons.key_round, size: 16), text: 'JWT Decoder'),
            Tab(icon: Icon(LucideIcons.binary, size: 16), text: 'Base64 & Hash'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _RegexTesterView(),
          _JsonFormatterView(),
          _JwtDecoderView(),
          _Base64HashView(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. REGEX TESTER
// ─────────────────────────────────────────────────────────────────────────────
class _RegexTesterView extends StatefulWidget {
  const _RegexTesterView();

  @override
  State<_RegexTesterView> createState() => _RegexTesterViewState();
}

class _RegexTesterViewState extends State<_RegexTesterView> {
  final _patternController = TextEditingController(text: r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
  final _testController = TextEditingController(text: 'Hello admin@quantum.ide, contact dev@google.com or support@company.org');
  bool _caseInsensitive = true;
  bool _multiLine = false;
  bool _dotAll = false;
  List<RegExpMatch> _matches = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _patternController.addListener(_evaluate);
    _testController.addListener(_evaluate);
    _evaluate();
  }

  @override
  void dispose() {
    _patternController.dispose();
    _testController.dispose();
    super.dispose();
  }

  void _evaluate() {
    final pattern = _patternController.text;
    final text = _testController.text;
    if (pattern.isEmpty) {
      setState(() {
        _matches = [];
        _error = null;
      });
      return;
    }

    try {
      final regExp = RegExp(
        pattern,
        caseSensitive: !_caseInsensitive,
        multiLine: _multiLine,
        dotAll: _dotAll,
      );
      final found = regExp.allMatches(text).toList();
      setState(() {
        _matches = found;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _matches = [];
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161927),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _error != null ? Colors.redAccent : Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Regular Expression', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 6),
              TextField(
                controller: _patternController,
                style: GoogleFonts.firaCode(color: const Color(0xFF00E5FF), fontSize: 13),
                decoration: const InputDecoration(
                  prefixText: '/',
                  suffixText: '/g',
                  prefixStyle: TextStyle(color: Colors.white38),
                  suffixStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  hintText: 'Enter regex pattern...',
                  hintStyle: TextStyle(color: Colors.white24),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('i (Case-Insensitive)'),
              selected: _caseInsensitive,
              onSelected: (v) {
                setState(() => _caseInsensitive = v);
                _evaluate();
              },
              backgroundColor: const Color(0xFF161927),
              selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              labelStyle: TextStyle(color: _caseInsensitive ? const Color(0xFF00E5FF) : Colors.white60, fontSize: 11),
            ),
            FilterChip(
              label: const Text('m (Multi-Line)'),
              selected: _multiLine,
              onSelected: (v) {
                setState(() => _multiLine = v);
                _evaluate();
              },
              backgroundColor: const Color(0xFF161927),
              selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              labelStyle: TextStyle(color: _multiLine ? const Color(0xFF00E5FF) : Colors.white60, fontSize: 11),
            ),
            FilterChip(
              label: const Text('s (Dot-All)'),
              selected: _dotAll,
              onSelected: (v) {
                setState(() => _dotAll = v);
                _evaluate();
              },
              backgroundColor: const Color(0xFF161927),
              selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              labelStyle: TextStyle(color: _dotAll ? const Color(0xFF00E5FF) : Colors.white60, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161927),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Test String', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _matches.isNotEmpty ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_matches.length} совпадений',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _matches.isNotEmpty ? const Color(0xFF10B981) : Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _testController,
                maxLines: 4,
                style: GoogleFonts.firaCode(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Enter test string...'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_matches.isNotEmpty) ...[
          Text('Найденные совпадения:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 8),
          ..._matches.asMap().entries.map((entry) {
            final idx = entry.key;
            final m = entry.value;
            final matchStr = _testController.text.substring(m.start, m.end);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2235),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF00E5FF).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text('#${idx + 1}', style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(matchStr, style: GoogleFonts.firaCode(color: Colors.white, fontSize: 12))),
                  IconButton(
                    icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white54),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: matchStr));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано!'), duration: Duration(seconds: 1)));
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. JSON / FORMATTER
// ─────────────────────────────────────────────────────────────────────────────
class _JsonFormatterView extends StatefulWidget {
  const _JsonFormatterView();

  @override
  State<_JsonFormatterView> createState() => _JsonFormatterViewState();
}

class _JsonFormatterViewState extends State<_JsonFormatterView> {
  final _controller = TextEditingController(text: '{"name":"QuantumIDE","version":"1.2.42","features":["terminal","editor","local_ai"],"config":{"theme":"dark","port":8080}}');
  String? _status;
  bool _isSuccess = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _formatJson() {
    try {
      final obj = json.decode(_controller.text);
      final pretty = const JsonEncoder.withIndent('  ').convert(obj);
      setState(() {
        _controller.text = pretty;
        _status = '✅ Валидный JSON успешно отформатирован';
        _isSuccess = true;
      });
    } catch (e) {
      setState(() {
        _status = '❌ Ошибка синтаксиса JSON: $e';
        _isSuccess = false;
      });
    }
  }

  void _minifyJson() {
    try {
      final obj = json.decode(_controller.text);
      final minified = json.encode(obj);
      setState(() {
        _controller.text = minified;
        _status = '⚡ JSON минифицирован в одну строку';
        _isSuccess = true;
      });
    } catch (e) {
      setState(() {
        _status = '❌ Ошибка синтаксиса JSON: $e';
        _isSuccess = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _formatJson,
                icon: const Icon(LucideIcons.code, size: 14),
                label: const Text('Prettify'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _minifyJson,
                icon: const Icon(LucideIcons.minimize_2, size: 14),
                label: const Text('Minify'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  textStyle: GoogleFonts.inter(fontSize: 12),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 18, color: Colors.white70),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _controller.text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано!'), duration: Duration(seconds: 1)));
                },
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash_2, size: 18, color: Colors.white70),
                onPressed: () => setState(() => _controller.clear()),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isSuccess ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status!,
                style: TextStyle(color: _isSuccess ? const Color(0xFF10B981) : Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141724),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style: GoogleFonts.firaCode(color: const Color(0xFF00E5FF), fontSize: 12),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. JWT DECODER
// ─────────────────────────────────────────────────────────────────────────────
class _JwtDecoderView extends StatefulWidget {
  const _JwtDecoderView();

  @override
  State<_JwtDecoderView> createState() => _JwtDecoderViewState();
}

class _JwtDecoderViewState extends State<_JwtDecoderView> {
  final _jwtController = TextEditingController();
  Map<String, dynamic>? _header;
  Map<String, dynamic>? _payload;
  String? _error;
  DateTime? _expiresAt;
  bool _isExpired = false;

  void _decodeJwt(String token) {
    final parts = token.trim().split('.');
    if (parts.length != 3) {
      setState(() {
        _header = null;
        _payload = null;
        _error = 'Неверный формат JWT (ожидается 3 части через точку).';
      });
      return;
    }

    try {
      String normalizeBase64(String str) {
        var output = str.replaceAll('-', '+').replaceAll('_', '/');
        switch (output.length % 4) {
          case 0: break;
          case 2: output += '=='; break;
          case 3: output += '='; break;
          default: throw Exception('Illegal base64url string');
        }
        return output;
      }

      final headerStr = utf8.decode(base64Decode(normalizeBase64(parts[0])));
      final payloadStr = utf8.decode(base64Decode(normalizeBase64(parts[1])));

      final h = json.decode(headerStr) as Map<String, dynamic>;
      final p = json.decode(payloadStr) as Map<String, dynamic>;

      DateTime? expDate;
      bool expired = false;
      if (p.containsKey('exp') && p['exp'] is int) {
        expDate = DateTime.fromMillisecondsSinceEpoch((p['exp'] as int) * 1000);
        expired = expDate.isBefore(DateTime.now());
      }

      setState(() {
        _header = h;
        _payload = p;
        _expiresAt = expDate;
        _isExpired = expired;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _header = null;
        _payload = null;
        _error = 'Ошибка декодирования токена: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF161927), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Вставьте JWT Токен', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 6),
              TextField(
                controller: _jwtController,
                maxLines: 3,
                style: GoogleFonts.firaCode(color: Colors.white, fontSize: 11),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'eyJh...'),
                onChanged: _decodeJwt,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
        if (_expiresAt != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isExpired ? Colors.redAccent.withValues(alpha: 0.15) : const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(_isExpired ? LucideIcons.circle_alert : LucideIcons.circle_check, size: 16, color: _isExpired ? Colors.redAccent : const Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(
                  _isExpired ? 'Токен ИСТЕК: $_expiresAt' : 'Токен АКТИВЕН до: $_expiresAt',
                  style: TextStyle(color: _isExpired ? Colors.redAccent : const Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
        if (_header != null) ...[
          const SizedBox(height: 16),
          Text('Header (Заголовок)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFFF4081))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF141724), borderRadius: BorderRadius.circular(8)),
            child: Text(const JsonEncoder.withIndent('  ').convert(_header), style: GoogleFonts.firaCode(color: const Color(0xFFFF80AB), fontSize: 12)),
          ),
        ],
        if (_payload != null) ...[
          const SizedBox(height: 16),
          Text('Payload (Данные)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF00E5FF))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF141724), borderRadius: BorderRadius.circular(8)),
            child: Text(const JsonEncoder.withIndent('  ').convert(_payload), style: GoogleFonts.firaCode(color: const Color(0xFF80D8FF), fontSize: 12)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. BASE64 & HASH
// ─────────────────────────────────────────────────────────────────────────────
class _Base64HashView extends StatefulWidget {
  const _Base64HashView();

  @override
  State<_Base64HashView> createState() => _Base64HashViewState();
}

class _Base64HashViewState extends State<_Base64HashView> {
  final _inputController = TextEditingController(text: 'QuantumIDE Next-Gen Mobile IDE');
  String _base64Encoded = '';
  String _md5Hash = '';
  String _sha1Hash = '';
  String _sha256Hash = '';

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_recalculate);
    _recalculate();
  }

  void _recalculate() {
    final text = _inputController.text;
    final bytes = utf8.encode(text);
    setState(() {
      _base64Encoded = base64Encode(bytes);
      _md5Hash = md5.convert(bytes).toString();
      _sha1Hash = sha1.convert(bytes).toString();
      _sha256Hash = sha256.convert(bytes).toString();
    });
  }

  Widget _hashCard(String title, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF161927), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white54),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано!'), duration: Duration(seconds: 1)));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(value, style: GoogleFonts.firaCode(fontSize: 11, color: Colors.white70)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF161927), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Исходный текст', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 6),
              TextField(
                controller: _inputController,
                maxLines: 3,
                style: GoogleFonts.firaCode(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Enter text...'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _hashCard('Base64 Encoded', _base64Encoded, const Color(0xFF00E5FF)),
        _hashCard('MD5 Hash', _md5Hash, Colors.orangeAccent),
        _hashCard('SHA-1 Hash', _sha1Hash, Colors.amberAccent),
        _hashCard('SHA-256 Hash', _sha256Hash, const Color(0xFF10B981)),
      ],
    );
  }
}
