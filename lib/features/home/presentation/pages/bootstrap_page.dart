import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/runtime_service.dart';

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkReady();
      _startInit();
    });
  }

  void _checkReady() {
    if (ref.read(runtimeServiceProvider).isInitialized) {
      context.go('/');
    }
  }

  Future<void> _startInit() async {
    final runtime = ref.read(runtimeServiceProvider);
    await runtime.init();
    if (mounted && runtime.isInitialized) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(runtimeServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.settings_input_component, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 40),
              Text(
                'QuantumIDE',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                runtime.status,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              LinearProgressIndicator(
                value: runtime.progress,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                color: theme.colorScheme.primary,
              ),
              if (runtime.status.startsWith('Error')) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => runtime.init(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  child: const Text('Retry'),
                ),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => runtime.reset(),
                child: Text(
                  'Clean Reinstall',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
