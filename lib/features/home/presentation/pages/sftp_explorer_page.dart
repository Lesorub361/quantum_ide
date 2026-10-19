import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

class SftpExplorerPage extends StatefulWidget {
  const SftpExplorerPage({super.key});

  @override
  State<SftpExplorerPage> createState() => _SftpExplorerPageState();
}

class _SftpExplorerPageState extends State<SftpExplorerPage> {
  final _hostController = TextEditingController(text: '');
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController(text: 'root');
  final _passController = TextEditingController();

  SSHClient? _client;
  SftpClient? _sftp;
  bool _isConnected = false;
  bool _isLoading = false;
  String _currentPath = '/';
  List<SftpName> _items = [];
  String? _errorMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passController.dispose();
    _sftp?.close();
    _client?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 22;
    final user = _userController.text.trim();
    final pass = _passController.text;

    if (host.isEmpty) {
      setState(() => _errorMessage = 'Введите адрес сервера (Host / IP)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 10));
      final client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
      );

      final sftp = await client.sftp();
      final items = await sftp.listdir(_currentPath);

      setState(() {
        _client = client;
        _sftp = sftp;
        _isConnected = true;
        _items = items..sort((a, b) {
          if (a.attr.isDirectory && !b.attr.isDirectory) return -1;
          if (!a.attr.isDirectory && b.attr.isDirectory) return 1;
          return a.filename.compareTo(b.filename);
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка подключения SSH/SFTP: $e';
      });
    }
  }

  Future<void> _navigate(String path) async {
    if (_sftp == null) return;
    setState(() => _isLoading = true);

    try {
      final items = await _sftp!.listdir(path);
      setState(() {
        _currentPath = path;
        _items = items..sort((a, b) {
          if (a.attr.isDirectory && !b.attr.isDirectory) return -1;
          if (!a.attr.isDirectory && b.attr.isDirectory) return 1;
          return a.filename.compareTo(b.filename);
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка перехода: $e';
      });
    }
  }

  void _disconnect() {
    _sftp?.close();
    _client?.close();
    setState(() {
      _client = null;
      _sftp = null;
      _isConnected = false;
      _items = [];
    });
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
            const Icon(LucideIcons.server, color: Color(0xFF00E5FF), size: 20),
            const SizedBox(width: 10),
            Text(
              'Remote SFTP File Explorer',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(LucideIcons.log_out, color: Colors.redAccent, size: 20),
              tooltip: 'Отключиться',
              onPressed: _disconnect,
            ),
        ],
      ),
      body: _isConnected ? _buildExplorerView() : _buildConnectForm(),
    );
  }

  Widget _buildConnectForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161927),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.globe, color: Color(0xFF00E5FF), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Подключение по SFTP',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'Удалённое управление файлами сервера',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _inputField('Host / IP', _hostController, hint: '192.168.1.100 or server.com'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _inputField('Port', _portController, hint: '22'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _inputField('User', _userController, hint: 'root or ubuntu'),
              const SizedBox(height: 14),
              _inputField('Password / Key', _passController, hint: '••••••••', obscure: true),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _connect,
                  icon: _isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(LucideIcons.zap, size: 18),
                  label: Text(_isLoading ? 'Подключение...' : 'Подключиться к серверу'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, {String hint = '', bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.white60)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2336),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: TextField(
            controller: ctrl,
            obscureText: obscure,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExplorerView() {
    return Column(
      children: [
        // Path bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF161927),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.arrow_up, color: Color(0xFF00E5FF), size: 18),
                onPressed: () {
                  if (_currentPath != '/' && _currentPath.isNotEmpty) {
                    final parent = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
                    _navigate(parent.isEmpty ? '/' : parent);
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentPath,
                  style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.refresh_cw, color: Colors.white60, size: 16),
                onPressed: () => _navigate(_currentPath),
              ),
            ],
          ),
        ),
        if (_isLoading)
          const LinearProgressIndicator(color: Color(0xFF00E5FF), backgroundColor: Colors.transparent),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              if (item.filename == '.' || item.filename == '..') return const SizedBox.shrink();

              final isDir = item.attr.isDirectory;
              final size = item.attr.size != null ? '${(item.attr.size! / 1024).toStringAsFixed(1)} KB' : '';

              return ListTile(
                leading: Icon(
                  isDir ? LucideIcons.folder : LucideIcons.file,
                  color: isDir ? Colors.amberAccent : Colors.cyanAccent,
                  size: 20,
                ),
                title: Text(item.filename, style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                subtitle: Text(
                  isDir ? 'Папка' : size,
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
                trailing: isDir ? const Icon(LucideIcons.chevron_right, color: Colors.white24, size: 16) : null,
                onTap: () {
                  if (isDir) {
                    final newPath = _currentPath == '/' ? '/${item.filename}' : '$_currentPath/${item.filename}';
                    _navigate(newPath);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Файл: ${item.filename} ($size)')),
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
