import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';

class AISettingsDialog extends ConsumerStatefulWidget {
  const AISettingsDialog({super.key});

  @override
  ConsumerState<AISettingsDialog> createState() => _AISettingsDialogState();
}

class _AISettingsDialogState extends ConsumerState<AISettingsDialog> {
  late String _selectedProviderId;
  late String _selectedModel;
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  List<String> _availableModels = [];
  bool _isLoadingModels = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final aiSvc = ref.read(aiServiceProvider);
    _selectedProviderId = aiSvc.selectedProviderId;
    _selectedModel = aiSvc.selectedModel;
    _keyController.text = aiSvc.getApiKey(_selectedProviderId);
    _urlController.text = aiSvc.getBaseUrl(_selectedProviderId);
    _loadModels();
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
      // Fallback
      setState(() {
        _availableModels = AiProviders.byId(_selectedProviderId).defaultModels;
        if (!_availableModels.contains(_selectedModel)) {
          _selectedModel = _availableModels.isNotEmpty ? _availableModels.first : '';
        }
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
                        });
                        _loadModels();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Model Selector
              Text(l10n.model, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),
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
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedModel.isNotEmpty && _availableModels.contains(_selectedModel) ? _selectedModel : null,
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

              // API Key
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
                      icon: Icon(_obscureKey ? LucideIcons.eye : LucideIcons.eye_off, size: 16, color: Colors.white38),
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
                  hintText: l10n.defaultHint(AiProviders.byId(_selectedProviderId).baseUrl),
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
                        await aiSvcNotifier.setModel(_selectedModel);
                        
                        if (AiProviders.byId(_selectedProviderId).requiresApiKey) {
                          await aiSvcNotifier.setApiKey(_selectedProviderId, _keyController.text.trim());
                        }
                        
                        if (_urlController.text.trim().isNotEmpty) {
                          await aiSvcNotifier.setBaseUrl(_selectedProviderId, _urlController.text.trim());
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
