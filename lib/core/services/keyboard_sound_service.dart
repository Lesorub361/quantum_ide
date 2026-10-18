import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum KeyboardSwitchType {
  off('Выключен', 'Без звука'),
  cherryBlue('Cherry MX Blue', 'Звонкий щелчок и клик'),
  holyPanda('Holy Panda / Brown', 'Глубокий тактильный thock'),
  linearRed('Linear Red / Topre', 'Мягкий и тихий стук');

  final String title;
  final String description;
  const KeyboardSwitchType(this.title, this.description);
}

class KeyboardSoundService {
  static const _prefKeySwitch = 'quantum_keyboard_switch';
  static const _prefKeyHaptic = 'quantum_keyboard_haptic';

  static KeyboardSwitchType _currentSwitch = KeyboardSwitchType.cherryBlue;
  static bool _hapticEnabled = true;
  static bool _initialized = false;

  static final Map<KeyboardSwitchType, String> _filePathCache = {};
  static final AudioPlayer _player = AudioPlayer();

  static KeyboardSwitchType get currentSwitch => _currentSwitch;
  static bool get hapticEnabled => _hapticEnabled;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSwitch = prefs.getString(_prefKeySwitch);
      if (savedSwitch != null) {
        _currentSwitch = KeyboardSwitchType.values.firstWhere(
          (e) => e.name == savedSwitch,
          orElse: () => KeyboardSwitchType.cherryBlue,
        );
      }
      _hapticEnabled = prefs.getBool(_prefKeyHaptic) ?? true;

      // Pre-synthesize and save to cache files (SoundPool on Android requires file sources for LOW_LATENCY)
      final tempDir = await getTemporaryDirectory();
      final soundDir = Directory(p.join(tempDir.path, 'quantum_sounds'));
      if (!await soundDir.exists()) {
        await soundDir.create(recursive: true);
      }

      final configs = {
        KeyboardSwitchType.cherryBlue: (freq: 2600.0, decay: 190.0, durationMs: 25, filename: 'click_cherry.wav'),
        KeyboardSwitchType.holyPanda: (freq: 750.0, decay: 90.0, durationMs: 35, filename: 'click_panda.wav'),
        KeyboardSwitchType.linearRed: (freq: 420.0, decay: 120.0, durationMs: 20, filename: 'click_linear.wav'),
      };

      for (final entry in configs.entries) {
        final file = File(p.join(soundDir.path, entry.value.filename));
        if (!await file.exists() || (await file.length()) == 0) {
          final bytes = _createClickWav(
            freq: entry.value.freq,
            decay: entry.value.decay,
            durationMs: entry.value.durationMs,
          );
          await file.writeAsBytes(bytes);
        }
        _filePathCache[entry.key] = file.path;
      }

      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setVolume(0.85);
      _initialized = true;
    } catch (_) {}
  }

  static Future<void> setSwitch(KeyboardSwitchType type) async {
    _currentSwitch = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySwitch, type.name);
  }

  static Future<void> setHaptic(bool enabled) async {
    _hapticEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyHaptic, enabled);
  }

  static void playClick() {
    if (_hapticEnabled) {
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }

    if (_currentSwitch == KeyboardSwitchType.off) return;

    final filePath = _filePathCache[_currentSwitch];
    if (filePath != null) {
      try {
        _player.play(DeviceFileSource(filePath), volume: 0.85).catchError((_) {});
      } catch (_) {}
    }
  }

  static Uint8List _createClickWav({
    required double freq,
    required double decay,
    required int durationMs,
  }) {
    const sampleRate = 22050;
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);

    // RIFF header
    buffer.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    buffer.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // Mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    buffer.setUint16(32, 2, Endian.little); // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample
    buffer.setUint32(36, 0x64617461, Endian.big); // "data"
    buffer.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * decay);
      // Double click impulse for blue, resonant thock for panda
      final clickImpulse = freq > 2000
          ? (math.sin(2 * math.pi * freq * t) + 0.4 * math.sin(2 * math.pi * (freq * 1.5) * t))
          : (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * (freq * 0.5) * t));
      final val = (clickImpulse * env * 27000).toInt().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, val, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  static Future<void> showSwitchSelectorDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131722),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.keyboard, color: Colors.amberAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Звук и тактильность',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Тактильная виброотдача', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Микровибрация при каждом нажатии', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      value: _hapticEnabled,
                      activeThumbColor: Colors.amberAccent,
                      onChanged: (val) {
                        setState(() {
                          setHaptic(val);
                        });
                        HapticFeedback.lightImpact();
                      },
                    ),
                    const Divider(color: Colors.white10),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('ПРОФИЛЬ СВИТЧЕЙ КЛАВИАТУРЫ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    ...KeyboardSwitchType.values.map((sw) {
                      final isSelected = sw == _currentSwitch;
                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        tileColor: isSelected ? Colors.amberAccent.withValues(alpha: 0.12) : null,
                        leading: Icon(
                          sw == KeyboardSwitchType.off ? LucideIcons.volume_x : LucideIcons.volume_2,
                          color: isSelected ? Colors.amberAccent : Colors.white38,
                          size: 20,
                        ),
                        title: Text(sw.title, style: TextStyle(color: isSelected ? Colors.amberAccent : Colors.white, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text(sw.description, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        trailing: isSelected ? const Icon(LucideIcons.check, color: Colors.amberAccent, size: 18) : null,
                        onTap: () {
                          setState(() {
                            setSwitch(sw);
                          });
                          playClick();
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Готово', style: TextStyle(color: Colors.amberAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
