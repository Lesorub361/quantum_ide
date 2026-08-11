import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/right_chat_panel.dart';

class AISettingsDialog extends ConsumerStatefulWidget {
  const AISettingsDialog({super.key});

  @override
  ConsumerState<AISettingsDialog> createState() => _AISettingsDialogState();
}

class _AISettingsDialogState extends ConsumerState<AISettingsDialog> {
  late String _selectedProviderId;
  late String _selectedModel;
  late LocalAiEngine _selectedLocalEngine;
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  List<String> _availableModels = [];
  bool _isLoadingModels = false;
  bool _obscureKey = true;
  bool _ollamaReachable = false;
  bool _checkingOllama = false;

  // Local AI parameters
  int _localThreads = 4;
  int _localGpuLayers = 0;
  bool _localUseFlashAttn = false;

  @override
  void initState() {
    super.initState();
    final aiSvc = ref.read(aiServiceProvider);
    _selectedProviderId = aiSvc.selectedProviderId;
    _selectedModel = aiSvc.selectedModel;
    _selectedLocalEngine = aiSvc.selectedLocalEngine;
    _keyController.text = aiSvc.getApiKey(_selectedProviderId);
    _urlController.text = aiSvc.getBaseUrl(_selectedProviderId);
    
    final localAiState = ref.read(localAiServiceProvider);
    _localThreads = localAiState.threads;
    _localGpuLayers = localAiState.gpuLayers;
    _localUseFlashAttn = localAiState.useFlashAttn;

    _loadModels();
    if (_selectedProviderId == 'local_edge' && _selectedLocalEngine == LocalAiEngine.ollama) {
      _checkOllamaStatus();
    }
  }

  Future<void> _checkOllamaStatus() async {
    setState(() => _checkingOllama = true);
    try {
      final aiSvc = ref.read(aiServiceProvider);
      final models = await aiSvc.fetchAvailableModels('local_edge');
      setState(() {
        _ollamaReachable = models.isNotEmpty;
        _checkingOllama = false;
      });
    } catch (_) {
      setState(() {
        _ollamaReachable = false;
        _checkingOllama = false;
      });
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _isLoadingModels = true;
    });
    try {
      final aiSvc = ref.read(aiServiceProvider);
      final models = await aiSvc.fetchAvailableModels(_selectedProviderId);
      setState(() {
        _availableModels = models;
        if (!_availableModels.contains(_selectedModel)) {
          _selectedModel = _availableModels.isNotEmpty ? _availableModels.first : '';
        }
      });
    } catch (e) {
      // For local_edge Ollama: show empty list with error instead of defaults
      final isOllamaProvider = _selectedProviderId == 'local_edge' &&
          _selectedLocalEngine == LocalAiEngine.ollama;
      setState(() {
        _availableModels = isOllamaProvider
            ? [] // Ollama unavailable — no fallback list
            : AiProviders.byId(_selectedProviderId).defaultModels;
        if (!_availableModels.contains(_selectedModel)) {
          _selectedModel = _availableModels.isNotEmpty ? _availableModels.first : '';
        }
        _ollamaReachable = false;
      });
    } finally {
      setState(() {
        _isLoadingModels = false;
      });
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiSvc = ref.watch(aiServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final isLocalEdge = _selectedProviderId == 'local_edge';
    final isOllamaEngine = isLocalEdge && _selectedLocalEngine == LocalAiEngine.ollama;

    return Dialog(
      backgroundColor: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.aiSettings,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white54, size: 18),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 20),

              // Provider Selector
              Text(l10n.provider, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedProviderId,
                    dropdownColor: const Color(0xFF1E2230),
                    isExpanded: true,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    items: AiProviders.all.map((p) {
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text('${p.logoEmoji}  ${p.displayName}'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedProviderId = val;
                          _keyController.text = aiSvc.getApiKey(val);
                          _urlController.text = aiSvc.getBaseUrl(val);
                          _selectedModel = AiProviders.byId(val).defaultModels.first;
                          _ollamaReachable = false;
                        });
                        _loadModels();
                        if (val == 'local_edge' && _selectedLocalEngine == LocalAiEngine.ollama) {
                          _checkOllamaStatus();
                        }
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Local AI Engine Selector (only when local_edge is selected)
              if (isLocalEdge) ...[
                Row(
                  children: [
                    Text(
                      'Local AI Engine',
                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                    ),
                    const Spacer(),
                    // Ollama status indicator
                    if (isOllamaEngine) ...[
                      if (_checkingOllama)
                        const SizedBox(
                          width: 8, height: 8,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.cyanAccent),
                        )
                      else
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _ollamaReachable
                                ? const Color(0xFF10B981) // green — running
                                : Colors.redAccent,
                          ),
                        ),
                      const SizedBox(width: 5),
                      Text(
                        _ollamaReachable ? 'Running' : 'Not found',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: _ollamaReachable ? const Color(0xFF10B981) : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          _checkOllamaStatus();
                          _loadModels();
                        },
                        child: const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.white38),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<LocalAiEngine>(
                      value: _selectedLocalEngine,
                      dropdownColor: const Color(0xFF1E2230),
                      isExpanded: true,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      items: LocalAiEngine.values.map((engine) {
                        return DropdownMenuItem<LocalAiEngine>(
                          value: engine,
                          child: Text(engine.displayName),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedLocalEngine = val;
                            _ollamaReachable = false;
                            _availableModels = [];
                            _selectedModel = '';
                            // Update URL to default for the engine
                            _urlController.text = val.defaultBaseUrl;
                          });
                          // Update engine in service immediately for correct URL resolution
                          ref.read(aiServiceProvider).setLocalEngine(val).then((_) {
                            _loadModels();
                            if (val == LocalAiEngine.ollama) {
                              _checkOllamaStatus();
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Hardware / NPU Acceleration Settings
                if (_selectedLocalEngine == LocalAiEngine.llamaServer) ...[
                  Text(
                    'Ускорение NPU / GPU / CPU',
                    style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  
                  // Threads slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Потоки процессора', style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
                      Text('$_localThreads', style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.purpleAccent,
                      inactiveTrackColor: Colors.white10,
                      thumbColor: Colors.cyanAccent,
                      overlayColor: Colors.cyanAccent.withValues(alpha: 0.2),
                      valueIndicatorColor: const Color(0xFF1E2230),
                    ),
                    child: Slider(
                      value: _localThreads.toDouble(),
                      min: 1,
                      max: 16,
                      divisions: 15,
                      onChanged: (val) {
                        setState(() {
                          _localThreads = val.toInt();
                        });
                      },
                    ),
                  ),
                  
                  // GPU / NPU Layers slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Слои на GPU/NPU', style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
                      Text(
                        _localGpuLayers == 0 ? 'CPU-only (0)' : '$_localGpuLayers',
                        style: GoogleFonts.jetBrainsMono(
                          color: _localGpuLayers == 0 ? Colors.white38 : Colors.cyanAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.purpleAccent,
                      inactiveTrackColor: Colors.white10,
                      thumbColor: Colors.cyanAccent,
                      overlayColor: Colors.cyanAccent.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _localGpuLayers.toDouble(),
                      min: 0,
                      max: 99,
                      divisions: 99,
                      onChanged: (val) {
                        setState(() {
                          _localGpuLayers = val.toInt();
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0, bottom: 10.0),
                    child: Text(
                      'Перенос слоев на GPU/NPU ускоряет инференс. Для NPU установите Vulkan/OpenCL и укажите кол-во слоев.',
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 9),
                    ),
                  ),
                  
                  // Flash Attention switch
                  SwitchListTile(
                    title: Text(
                      'Flash Attention',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                    ),
                    subtitle: Text(
                      'Значительно ускоряет генерацию, уменьшая потребление памяти.',
                      style: GoogleFonts.inter(color: Colors.white30, fontSize: 9),
                    ),
                    value: _localUseFlashAttn,
                    activeThumbColor: Colors.cyanAccent,
                    activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.5),
                    inactiveThumbColor: Colors.white38,
                    inactiveTrackColor: Colors.white10,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (val) {
                      setState(() {
                        _localUseFlashAttn = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ],

              // Model Selector
              Text(l10n.model, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),

              // Ollama not running warning
              if (isOllamaEngine && !_isLoadingModels && !_ollamaReachable && _availableModels.isEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.triangle_alert, size: 14, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ollama не запущена. Запустите Ollama и нажмите ↻ для обновления списка моделей.',
                          style: GoogleFonts.inter(color: Colors.orange, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: _isLoadingModels
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                          ),
                        ),
                      )
                    : _availableModels.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              isOllamaEngine
                                  ? 'Нет доступных моделей. Установите модели через: ollama pull <model>'
                                  : 'Нет доступных моделей',
                              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedModel.isNotEmpty && _availableModels.contains(_selectedModel)
                                  ? _selectedModel
                                  : null,
                              dropdownColor: const Color(0xFF1E2230),
                              isExpanded: true,
                              style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 12),
                              items: _availableModels.map((m) {
                                return DropdownMenuItem<String>(
                                  value: m,
                                  child: Text(m),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedModel = val;
                                  });
                                }
                              },
                            ),
                          ),
              ),
              const SizedBox(height: 16),

              // API Key (only for providers that require it)
              if (AiProviders.byId(_selectedProviderId).requiresApiKey) ...[
                Text(l10n.apiKey, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: _keyController,
                  obscureText: _obscureKey,
                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: AiProviders.byId(_selectedProviderId).apiKeyHint,
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.cyanAccent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey ? LucideIcons.eye : LucideIcons.eye_off,
                          size: 16, color: Colors.white38),
                      onPressed: () {
                        setState(() {
                          _obscureKey = !_obscureKey;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Custom Base URL
              Text(l10n.customBaseUrl, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: isLocalEdge
                      ? _selectedLocalEngine.defaultBaseUrl
                      : l10n.defaultHint(AiProviders.byId(_selectedProviderId).baseUrl),
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyanAccent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.cancel, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final aiSvcNotifier = ref.read(aiServiceProvider);

                        await aiSvcNotifier.setProvider(_selectedProviderId);
                        ref.read(activeAiProviderIdProvider.notifier).state = _selectedProviderId;

                        if (_selectedModel.isNotEmpty) {
                          await aiSvcNotifier.setModel(_selectedModel);
                          ref.read(activeAiModelProvider.notifier).state = _selectedModel;
                        }

                        if (AiProviders.byId(_selectedProviderId).requiresApiKey) {
                          await aiSvcNotifier.setApiKey(_selectedProviderId, _keyController.text.trim());
                        }

                        if (_urlController.text.trim().isNotEmpty) {
                          await aiSvcNotifier.setBaseUrl(_selectedProviderId, _urlController.text.trim());
                        }

                        if (_selectedProviderId == 'local_edge') {
                          await aiSvcNotifier.setLocalEngine(_selectedLocalEngine);
                          await ref.read(localAiServiceProvider.notifier).updateSettings(
                            threads: _localThreads,
                            gpuLayers: _localGpuLayers,
                            useFlashAttn: _localUseFlashAttn,
                          );
                        }

                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: Text(l10n.save, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
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
}
