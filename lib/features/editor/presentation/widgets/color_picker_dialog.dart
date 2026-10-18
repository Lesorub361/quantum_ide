import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modal dialog for visual color selection in code editor using flutter_colorpicker.
class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final Function(String hexCode, String flutterCode) onColorSelected;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
  });

  static Future<void> show(
    BuildContext context, {
    Color initialColor = const Color(0xFF2196F3),
    required Function(String hexCode, String flutterCode) onColorSelected,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ColorPickerDialog(
        initialColor: initialColor,
        onColorSelected: onColorSelected,
      ),
    );
  }

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _currentColor;
  int _pickerMode = 0; // 0: Слайдеры/Колесо, 1: Material блоки

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
  }

  String get _hexString =>
      '#${_currentColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  String get _flutterCode =>
      'Color(0x${_currentColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF131722),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      actionsPadding: const EdgeInsets.all(12),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.pinkAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.palette, color: Colors.pinkAccent, size: 16),
          ),
          const SizedBox(width: 8),
          Text(
            'Выбор цвета',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          // Mode switcher
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Колесо', style: TextStyle(fontSize: 10))),
              ButtonSegment(value: 1, label: Text('Блоки', style: TextStyle(fontSize: 10))),
            ],
            selected: {_pickerMode},
            onSelectionChanged: (set) => setState(() => _pickerMode = set.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (_pickerMode == 0)
              ColorPicker(
                pickerColor: _currentColor,
                onColorChanged: (color) => setState(() => _currentColor = color),
                colorPickerWidth: 260,
                pickerAreaHeightPercent: 0.65,
                enableAlpha: true,
                displayThumbColor: true,
                paletteType: PaletteType.hsvWithHue,
                labelTypes: const [],
                pickerAreaBorderRadius: BorderRadius.circular(10),
              )
            else
              BlockPicker(
                pickerColor: _currentColor,
                onColorChanged: (color) => setState(() => _currentColor = color),
              ),
            const SizedBox(height: 12),
            // Preview card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0F17),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _currentColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hexString,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.cyanAccent,
                          ),
                        ),
                        Text(
                          _flutterCode,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white60),
                    tooltip: 'Скопировать HEX',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Clipboard.setData(ClipboardData(text: _hexString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('HEX скопирован'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
        FilledButton.tonal(
          onPressed: () {
            widget.onColorSelected(_hexString, _flutterCode);
            Navigator.of(context).pop();
          },
          child: const Text('Вставить HEX'),
        ),
        FilledButton(
          onPressed: () {
            widget.onColorSelected(_flutterCode, _flutterCode);
            Navigator.of(context).pop();
          },
          child: const Text('Вставить Color()'),
        ),
      ],
    );
  }
}
