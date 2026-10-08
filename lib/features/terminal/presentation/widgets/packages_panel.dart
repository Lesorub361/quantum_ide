import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/packages_manager_view.dart';

class SidebarPackagesPanel extends ConsumerWidget {
  const SidebarPackagesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const PackagesManagerView();
  }
}
