import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/services/runtime_service.dart';
import '../../../../core/services/workspace_service.dart';
import '../../../../core/utils/path_mapper.dart';

class ApkSignerWidget extends ConsumerStatefulWidget {
  const ApkSignerWidget({super.key});

  @override
  ConsumerState<ApkSignerWidget> createState() => _ApkSignerWidgetState();
}

class _ApkSignerWidgetState extends ConsumerState<ApkSignerWidget> {
  // Common states
  bool _isLoading = false;
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  // Found files
  List<String> _localApks = [];
  List<String> _localKeystores = [];

  // Dropdown selections
  String? _selectedApk;
  String? _selectedKeystore;

  // Custom paths (if chosen via picker or entered manually)
  final TextEditingController _customApkController = TextEditingController();
  final TextEditingController _customKeystoreController = TextEditingController();

  // Signing form inputs
  final TextEditingController _ksPasswordController = TextEditingController(text: 'android');
  final TextEditingController _keyAliasController = TextEditingController(text: 'key');
  final TextEditingController _keyPasswordController = TextEditingController(text: 'android');
  final TextEditingController _signedApkNameController = TextEditingController();

  // Keystore generator inputs
  final TextEditingController _genNameController = TextEditingController(text: 'release.jks');
  final TextEditingController _genKsPassController = TextEditingController(text: 'android');
  final TextEditingController _genAliasController = TextEditingController(text: 'key');
  final TextEditingController _genKeyPassController = TextEditingController(text: 'android');
  final TextEditingController _genCnController = TextEditingController(text: 'Android Developer');
  final TextEditingController _genOuController = TextEditingController(text: 'Mobile');
  final TextEditingController _genOController = TextEditingController(text: 'QuantumIDE');
  final TextEditingController _genLController = TextEditingController(text: 'Moscow');
  final TextEditingController _genSController = TextEditingController(text: 'Moscow');
  final TextEditingController _genCController = TextEditingController(text: 'RU');

  String? _lastSignedApkPath;

  @override
  void initState() {
    super.initState();
    _scanWorkspaceFiles();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _customApkController.dispose();
    _customKeystoreController.dispose();
    _ksPasswordController.dispose();
    _keyAliasController.dispose();
    _keyPasswordController.dispose();
    _signedApkNameController.dispose();
    _genNameController.dispose();
    _genKsPassController.dispose();
    _genAliasController.dispose();
    _genKeyPassController.dispose();
    _genCnController.dispose();
    _genOuController.dispose();
    _genOController.dispose();
    _genLController.dispose();
    _genSController.dispose();
    _genCController.dispose();
    super.dispose();
  }

  void _scanWorkspaceFiles() {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    try {
      final dir = Directory(workspacePath);
      if (!dir.existsSync()) return;

      final List<String> apks = [];
      final List<String> keystores = [];

      final files = dir.listSync(recursive: true);
      for (final entity in files) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.apk') {
            apks.add(entity.path);
          } else if (ext == '.jks' || ext == '.keystore') {
            keystores.add(entity.path);
          }
        }
      }

      setState(() {
        _localApks = apks;
        _localKeystores = keystores;

        if (apks.isNotEmpty) {
          _selectedApk = apks.first;
          _updateSignedApkDefaultName(_selectedApk!);
        }
        if (keystores.isNotEmpty) {
          _selectedKeystore = keystores.first;
        }
      });
    } catch (e) {
      _addLog('Ошибка сканирования проекта: $e', isError: true);
    }
  }

  void _updateSignedApkDefaultName(String inputApkPath) {
    final originalName = p.basenameWithoutExtension(inputApkPath);
    if (!originalName.endsWith('-signed')) {
      _signedApkNameController.text = '$originalName-signed.apk';
    } else {
      _signedApkNameController.text = '$originalName.apk';
    }
  }

  void _addLog(String text, {bool isError = false, bool isSuccess = false}) {
    setState(() {
      final prefix = isError ? '[ERROR] ' : (isSuccess ? '[SUCCESS] ' : '[LOG] ');
      _logs.add('$prefix$text');
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _toGuestPath(String hostPath, RuntimeService runtime) {
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  Future<void> _pickFile({required bool isApk}) async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: isApk ? ['apk'] : ['jks', 'keystore'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          if (isApk) {
            _customApkController.text = path;
            _selectedApk = 'custom';
            _updateSignedApkDefaultName(path);
          } else {
            _customKeystoreController.text = path;
            _selectedKeystore = 'custom';
          }
        });
        _addLog('Выбран файл через FilePicker: $path');
      }
    } catch (e) {
      _addLog('Ошибка выбора файла: $e', isError: true);
    }
  }

  Future<void> _signApk() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) {
      _addLog('Нет открытого проекта', isError: true);
      return;
    }

    final String? apkPath = _selectedApk == 'custom' ? _customApkController.text : _selectedApk;
    final String? keystorePath = _selectedKeystore == 'custom' ? _customKeystoreController.text : _selectedKeystore;

    if (apkPath == null || apkPath.isEmpty) {
      _addLog('Не выбран исходный APK', isError: true);
      return;
    }
    if (keystorePath == null || keystorePath.isEmpty) {
      _addLog('Не выбран файл Keystore', isError: true);
      return;
    }

    final ksPass = _ksPasswordController.text;
    final alias = _keyAliasController.text;
    final keyPass = _keyPasswordController.text;
    final signedName = _signedApkNameController.text.trim();

    if (ksPass.isEmpty || alias.isEmpty || keyPass.isEmpty || signedName.isEmpty) {
      _addLog('Заполните все поля подписи', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final runtime = ref.read(runtimeServiceProvider);
      
      final String inputApkGuest = _toGuestPath(apkPath, runtime);
      final String keystoreGuest = _toGuestPath(keystorePath, runtime);
      
      // Output signed APK inside project root or relative path
      final String outputApkHost = p.join(p.dirname(apkPath), signedName);
      final String outputApkGuest = _toGuestPath(outputApkHost, runtime);

      _addLog('Подпись APK: ${p.basename(apkPath)}...');
      _addLog('Файл ключа: ${p.basename(keystorePath)} (alias: $alias)');

      final signCmd = 'apksigner sign '
          '--ks "$keystoreGuest" '
          '--ks-key-alias "$alias" '
          '--ks-pass pass:"$ksPass" '
          '--key-pass pass:"$keyPass" '
          '--out "$outputApkGuest" "$inputApkGuest"';

      _addLog('Запуск apksigner...');
      final output = await runtime.runCommand(signCmd);
      if (output.isNotEmpty) {
        _addLog(output);
      }

      // Verify the signed APK
      _addLog('Верификация подписи...');
      final verifyCmd = 'apksigner verify -v "$outputApkGuest"';
      final verifyOutput = await runtime.runCommand(verifyCmd);
      _addLog(verifyOutput);

      if (verifyOutput.contains('Verified using v1 scheme') || 
          verifyOutput.contains('Verified using v2 scheme') || 
          verifyOutput.contains('Verified using v3 scheme') ||
          verifyOutput.toLowerCase().contains('verified')) {
        _addLog('APK успешно подписан и верифицирован!', isSuccess: true);
        setState(() {
          _lastSignedApkPath = outputApkHost;
        });
        _scanWorkspaceFiles();
      } else {
        _addLog('Подпись не верифицирована или произошла ошибка.', isError: true);
      }
    } catch (e) {
      _addLog('Ошибка при подписи APK: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateKeystore() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) {
      _addLog('Нет открытого проекта', isError: true);
      return;
    }

    final name = _genNameController.text.trim();
    final ksPass = _genKsPassController.text;
    final alias = _genAliasController.text.trim();
    final keyPass = _genKeyPassController.text;

    if (name.isEmpty || ksPass.isEmpty || alias.isEmpty || keyPass.isEmpty) {
      _addLog('Заполните ключевые поля генерации', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final runtime = ref.read(runtimeServiceProvider);
      
      final hostKeystorePath = p.join(workspacePath, name);
      final guestKeystorePath = _toGuestPath(hostKeystorePath, runtime);

      // Build DN string
      final cn = _genCnController.text;
      final ou = _genOuController.text;
      final o = _genOController.text;
      final l = _genLController.text;
      final s = _genSController.text;
      final c = _genCController.text;
      final dname = 'CN=$cn, OU=$ou, O=$o, L=$l, S=$s, C=$c';

      _addLog('Генерация Keystore: $name...');
      
      // Run keytool command
      final genCmd = 'keytool -genkeypair -v '
          '-keystore "$guestKeystorePath" '
          '-keyalg RSA -keysize 2048 -validity 10000 '
          '-alias "$alias" '
          '-storepass "$ksPass" '
          '-keypass "$keyPass" '
          '-dname "$dname"';

      final output = await runtime.runCommand(genCmd);
      if (output.isNotEmpty) {
        _addLog(output);
      }

      if (File(hostKeystorePath).existsSync()) {
        _addLog('Keystore успешно создан по пути: $name', isSuccess: true);
        _scanWorkspaceFiles();
      } else {
        _addLog('Не удалось создать файл Keystore.', isError: true);
      }
    } catch (e) {
      _addLog('Ошибка при генерации Keystore: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _installApk(String apkPath) async {
    try {
      if (await File(apkPath).exists()) {
        _addLog('Запуск установки APK: ${p.basename(apkPath)}');
        final result = await OpenFilex.open(apkPath);
        _addLog('Результат установки: ${result.message}');
      } else {
        _addLog('Файл APK не найден: $apkPath', isError: true);
      }
    } catch (e) {
      _addLog('Ошибка установки: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Subtabs for APK Signer & Generator
          Container(
            color: Colors.white.withValues(alpha: 0.02),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorColor: Colors.cyanAccent,
              labelColor: Colors.cyanAccent,
              unselectedLabelColor: Colors.white38,
              labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(
                  icon: Icon(LucideIcons.pen_tool, size: 16),
                  text: 'Подпись APK',
                ),
                Tab(
                  icon: Icon(LucideIcons.key_round, size: 16),
                  text: 'Создать Keystore',
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              children: [
                _buildSignTab(),
                _buildGenerateTab(),
              ],
            ),
          ),

          // Log Output Section at the bottom
          _buildLogsPanel(),
        ],
      ),
    );
  }

  Widget _buildSignTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Шаг 1: Выберите APK для подписи'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedApk,
                      dropdownColor: const Color(0xFF13161C),
                      hint: const Text('Выберите APK', style: TextStyle(color: Colors.white24, fontSize: 13)),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      isExpanded: true,
                      items: [
                        ..._localApks.map((path) => DropdownMenuItem(
                          value: path,
                          child: Text(p.basename(path), overflow: TextOverflow.ellipsis),
                        )),
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Text('Указать свой путь...'),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedApk = val;
                          if (val != 'custom' && val != null) {
                            _updateSignedApkDefaultName(val);
                          }
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(LucideIcons.folder_open, size: 18),
                onPressed: () => _pickFile(isApk: true),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                  foregroundColor: Colors.cyanAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          if (_selectedApk == 'custom') ...[
            const SizedBox(height: 8),
            _buildTextField(
              controller: _customApkController,
              hintText: 'Полный путь к APK файлу на устройстве',
              icon: LucideIcons.file_code,
              onChanged: (val) => _updateSignedApkDefaultName(val),
            ),
          ],
          
          const SizedBox(height: 16),
          _buildSectionHeader('Шаг 2: Выберите ключ (Keystore)'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedKeystore,
                      dropdownColor: const Color(0xFF13161C),
                      hint: const Text('Выберите Keystore', style: TextStyle(color: Colors.white24, fontSize: 13)),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      isExpanded: true,
                      items: [
                        ..._localKeystores.map((path) => DropdownMenuItem(
                          value: path,
                          child: Text(p.basename(path), overflow: TextOverflow.ellipsis),
                        )),
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Text('Указать свой путь...'),
                        ),
                      ],
                      onChanged: (val) => setState(() => _selectedKeystore = val),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(LucideIcons.folder_open, size: 18),
                onPressed: () => _pickFile(isApk: false),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                  foregroundColor: Colors.cyanAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          if (_selectedKeystore == 'custom') ...[
            const SizedBox(height: 8),
            _buildTextField(
              controller: _customKeystoreController,
              hintText: 'Полный путь к файлу .jks/.keystore',
              icon: LucideIcons.key_round,
            ),
          ],

          const SizedBox(height: 16),
          _buildSectionHeader('Шаг 3: Настройки подписи'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _ksPasswordController,
            hintText: 'Пароль Keystore',
            icon: LucideIcons.lock,
            obscureText: true,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _keyAliasController,
                  hintText: 'Key Alias (псевдоним)',
                  icon: LucideIcons.user,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  controller: _keyPasswordController,
                  hintText: 'Пароль Key Alias',
                  icon: LucideIcons.lock_keyhole,
                  obscureText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _signedApkNameController,
            hintText: 'Имя выходного APK-файла',
            icon: LucideIcons.package_check,
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _signApk,
                  icon: _isLoading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(LucideIcons.pen_tool, size: 16),
                  label: Text('Подписать APK', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_lastSignedApkPath != null) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _installApk(_lastSignedApkPath!),
                  icon: const Icon(LucideIcons.download, size: 16),
                  label: Text('Установить', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _scanWorkspaceFiles,
            icon: const Icon(LucideIcons.refresh_cw, size: 14),
            label: Text('Обновить список файлов проекта', style: GoogleFonts.inter(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              foregroundColor: Colors.white70,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Параметры нового ключа (Keystore)'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _genNameController,
            hintText: 'Имя файла (например, release.jks)',
            icon: LucideIcons.file_key,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _genKsPassController,
            hintText: 'Пароль хранилища (минимум 6 символов)',
            icon: LucideIcons.lock,
            obscureText: true,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _genAliasController,
                  hintText: 'Алиас ключа (например, key)',
                  icon: LucideIcons.user,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  controller: _genKeyPassController,
                  hintText: 'Пароль алиаса',
                  icon: LucideIcons.lock_keyhole,
                  obscureText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Информация о разработчике (DN)'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _genCnController,
            hintText: 'Имя и фамилия (CN)',
            icon: LucideIcons.user_check,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _genOuController,
                  hintText: 'Отдел (OU)',
                  icon: LucideIcons.briefcase,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  controller: _genOController,
                  hintText: 'Организация (O)',
                  icon: LucideIcons.building,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _genLController,
                  hintText: 'Город (L)',
                  icon: LucideIcons.map_pin,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  controller: _genSController,
                  hintText: 'Штат/Область (S)',
                  icon: LucideIcons.map,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: _buildTextField(
                  controller: _genCController,
                  hintText: 'Код страны (C)',
                  icon: LucideIcons.globe,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _generateKeystore,
              icon: _isLoading 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(LucideIcons.key, size: 16),
              label: Text('Сгенерировать Keystore', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          prefixIcon: Icon(icon, size: 16, color: Colors.white30),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildLogsPanel() {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF07090C),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Console header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.white.withValues(alpha: 0.01),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.terminal, size: 13, color: Colors.cyanAccent),
                    const SizedBox(width: 6),
                    Text(
                      'ЛОГ ПОДПИСИ И ГЕНЕРАЦИИ',
                      style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash_2, size: 14, color: Colors.white38),
                  onPressed: () => setState(() => _logs.clear()),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  tooltip: 'Очистить лог',
                ),
              ],
            ),
          ),
          
          // Log output lines
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Здесь будет выведен лог выполнения операций подписи.',
                      style: TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color textColor = Colors.white70;
                      if (log.startsWith('[ERROR]')) {
                        textColor = Colors.redAccent;
                      } else if (log.startsWith('[SUCCESS]')) {
                        textColor = Colors.greenAccent;
                      }
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          log,
                          style: GoogleFonts.firaCode(
                            color: textColor,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
