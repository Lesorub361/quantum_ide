import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/core/services/device_preview_service.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

class DevicePreviewPage extends ConsumerStatefulWidget {
  const DevicePreviewPage({super.key});

  @override
  ConsumerState<DevicePreviewPage> createState() => _DevicePreviewPageState();
}

class _DevicePreviewPageState extends ConsumerState<DevicePreviewPage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicePreviewProvider);
    final service = ref.read(devicePreviewProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.purpleAccent.withValues(alpha: 0.12), Colors.transparent],
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: theme.scaffoldBackgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(LucideIcons.arrow_left, color: theme.colorScheme.onSurface),
                  onPressed: () => context.go('/'),
                ),
                title: Row(
                  children: [
                    const Icon(LucideIcons.smartphone, size: 18, color: Colors.purpleAccent),
                    const SizedBox(width: 8),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Colors.purpleAccent, Colors.deepPurpleAccent],
                      ).createShader(b),
                      child: Text(
                        'Device Preview',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildDeviceSelector(state, service),
                    const SizedBox(height: 16),
                    _buildPreviewFrame(state, service),
                    const SizedBox(height: 16),
                    _buildControls(state, service),
                    const SizedBox(height: 16),
                    _buildOrientationToggle(state, service),
                    const SizedBox(height: 16),
                    _buildTextScaleSlider(state, service),
                    const SizedBox(height: 16),
                    _buildLocalePicker(state, service),
                    const SizedBox(height: 16),
                    _buildDisplayInfo(state),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector(DevicePreviewState state, DevicePreviewService service) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.monitor_smartphone, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text('Device', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          ...service.devicesByBrand.map((device) {
            final isSelected = state.selectedDeviceId == device.id && !state.useCustomSize;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => service.setDevice(device.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.purpleAccent.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? Colors.purpleAccent.withValues(alpha: 0.3) : Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      Icon(_getDeviceIcon(device), size: 16, color: isSelected ? Colors.purpleAccent : theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(device.name, style: GoogleFonts.inter(fontSize: 13, color: isSelected ? Colors.purpleAccent : theme.colorScheme.onSurface)),
                      ),
                      Text(
                        '${device.width.toInt()}×${device.height.toInt()}',
                        style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => service.toggleCustomSize(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: state.useCustomSize ? Colors.purpleAccent.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: state.useCustomSize ? Colors.purpleAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.ruler, size: 16, color: state.useCustomSize ? Colors.purpleAccent : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Custom Size', style: GoogleFonts.inter(fontSize: 13, color: state.useCustomSize ? Colors.purpleAccent : theme.colorScheme.onSurface)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(DevicePreset device) {
    if (device.id.contains('ipad')) return LucideIcons.tablet;
    if (device.brand == 'Samsung' && device.id.contains('fold')) return LucideIcons.layout_grid;
    return LucideIcons.smartphone;
  }

  Widget _buildPreviewFrame(DevicePreviewState state, DevicePreviewService service) {
    final theme = Theme.of(context);
    final width = state.displayWidth;
    final height = state.displayHeight;
    return Center(
      child: Container(
        width: width + 16,
        height: height + 16,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.purpleAccent.withValues(alpha: 0.1), blurRadius: 30, spreadRadius: 5),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.smartphone, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text(
                        '${state.effectiveWidth.toInt()} × ${state.effectiveHeight.toInt()}',
                        style: GoogleFonts.inter(fontSize: 14, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      ),
                      Text(
                        '${state.localeCode.toUpperCase()} · ${state.textScaleFactor.toStringAsFixed(1)}x',
                        style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      ),
                    ],
                  ),
                ),
                if (state.showGrid) _buildGridOverlay(state),
                if (state.showTouchArea) _buildTouchOverlay(state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridOverlay(DevicePreviewState state) {
    return CustomPaint(
      size: Size(state.displayWidth, state.displayHeight),
      painter: _GridPainter(),
    );
  }

  Widget _buildTouchOverlay(DevicePreviewState state) {
    return Positioned(
      bottom: 8,
      left: state.displayWidth / 2 - 20,
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Widget _buildControls(DevicePreviewState state, DevicePreviewService service) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.sliders_horizontal, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text('Scale', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
              const Spacer(),
              Text('${(state.scaleFactor * 100).toInt()}%', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.purpleAccent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.purpleAccent,
              overlayColor: Colors.purpleAccent.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: state.scaleFactor,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: (v) => service.setScaleFactor(v),
            ),
          ),
          if (state.useCustomSize) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _numberInput('Width', state.customWidth, (v) => service.setCustomSize(v, state.customHeight)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberInput('Height', state.customHeight, (v) => service.setCustomSize(state.customWidth, v)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _toggleButton('Grid', LucideIcons.layout_grid, state.showGrid, () => service.toggleGrid()),
              const SizedBox(width: 8),
              _toggleButton('Touch', LucideIcons.pointer, state.showTouchArea, () => service.toggleTouchArea()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberInput(String label, double value, ValueChanged<double> onChanged) {
    final controller = TextEditingController(text: value.toInt().toString());
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onSubmitted: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  Widget _toggleButton(String label, IconData icon, bool isActive, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.purpleAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? Colors.purpleAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? Colors.purpleAccent : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: isActive ? Colors.purpleAccent : theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrientationToggle(DevicePreviewState state, DevicePreviewService service) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(LucideIcons.rotate_cw, size: 14, color: Colors.purpleAccent),
          const SizedBox(width: 8),
          Text('Orientation', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
          const Spacer(),
          GestureDetector(
            onTap: () => service.toggleOrientation(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                state.isLandscape ? 'Landscape' : 'Portrait',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextScaleSlider(DevicePreviewState state, DevicePreviewService service) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.type, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text('Text Scale', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
              const Spacer(),
              Text('${state.textScaleFactor.toStringAsFixed(1)}x', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.purpleAccent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.purpleAccent,
              overlayColor: Colors.purpleAccent.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: state.textScaleFactor,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              onChanged: (v) => service.setTextScaleFactor(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalePicker(DevicePreviewState state, DevicePreviewService service) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.languages, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text('Locale', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DevicePreviewService.knownLocales.map((locale) {
              final isSelected = state.localeCode == locale.$1;
              return GestureDetector(
                onTap: () => service.setLocale(locale.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.purpleAccent.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? Colors.purpleAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text(
                    '${locale.$1.toUpperCase()} · ${locale.$2}',
                    style: GoogleFonts.inter(fontSize: 11, color: isSelected ? Colors.purpleAccent : theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayInfo(DevicePreviewState state) {
    final theme = Theme.of(context);
    final device = ref.read(devicePreviewProvider.notifier).selectedDevice;
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.info, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text('Display Info', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 8),
          _infoRow('Logical Size', '${state.effectiveWidth.toInt()} × ${state.effectiveHeight.toInt()}'),
          if (device != null) _infoRow('DPR', '${device.devicePixelRatio}'),
          _infoRow('Scale', '${(state.scaleFactor * 100).toInt()}%'),
          _infoRow('Display Size', '${state.displayWidth.toInt()} × ${state.displayHeight.toInt()}'),
          _infoRow('Orientation', state.isLandscape ? 'Landscape' : 'Portrait'),
          _infoRow('Text Scale', '${state.textScaleFactor.toStringAsFixed(1)}x'),
          _infoRow('Locale', state.localeCode.toUpperCase()),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
