import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/environment_service.dart';
import 'package:quantum_ide/core/utils/adaptive_dialog_helper.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

/// Shows the file-tree sort mode popup menu anchored to [context].
Future<void> showSortMenu(BuildContext context, WidgetRef ref) async {
  final button = context.findRenderObject() as RenderBox;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );

  final result = await showMenu<FileSortMode>(
    context: context,
    position: position,
    items: [
      PopupMenuItem(
        value: FileSortMode.name,
        child: Text(AppLocalizations.of(context)!.sortByName),
      ),
      PopupMenuItem(
        value: FileSortMode.size,
        child: Text(AppLocalizations.of(context)!.sortBySize),
      ),
      PopupMenuItem(
        value: FileSortMode.date,
        child: Text(AppLocalizations.of(context)!.sortByDate),
      ),
    ],
  );
  if (result != null) {
    ref.read(fileSortModeProvider.notifier).state = result;
  }
}

/// Prompts the user for a new file or folder name and creates it under [basePath].
Future<void> showCreateDialog(
  BuildContext context,
  WidgetRef ref,
  String basePath,
  bool isDir,
) async {
  final controller = TextEditingController();
  try {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isDir
              ? AppLocalizations.of(context)!.newFolder
              : AppLocalizations.of(context)!.newFile,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isDir
                ? AppLocalizations.of(context)!.nameFolderHint
                : AppLocalizations.of(context)!.nameFileHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final newPath = p.join(basePath, name);
      if (isDir) {
        await Directory(newPath).create();
      } else {
        await File(newPath).create();
      }

      ref.read(expandedFoldersProvider.notifier).setExpanded({
        ...ref.read(expandedFoldersProvider),
        basePath,
      });
    }
  } finally {
    controller.dispose();
  }
}

/// Displays the adaptive bottom sheet with system environment diagnostics and repair actions.
void showEnvironmentBottomSheet(BuildContext context, WidgetRef ref) {
  AdaptiveDialogHelper.showAdaptiveSheet(
    context: context,
    backgroundColor: const Color(0xff18181b),
    builder: (context) {
      return Consumer(
        builder: (context, ref, _) {
          final envState = ref.watch(environmentProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.systemEnv,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          if (envState.isChecking)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blueAccent,
                              ),
                            )
                          else
                            IconButton(
                              icon: const Icon(
                                LucideIcons.refresh_cw,
                                size: 18,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () => ref
                                  .read(environmentProvider.notifier)
                                  .checkEnvironment(),
                            ),
                          IconButton(
                            icon: const Icon(
                              LucideIcons.wrench,
                              size: 18,
                              color: Colors.orangeAccent,
                            ),
                            tooltip: AppLocalizations.of(
                              context,
                            )!.fixEnvironmentArm64,
                            onPressed: () => ref
                                .read(environmentProvider.notifier)
                                .fixEnvironment(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: envState.tools
                            .map(
                              (tool) => Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: tool.isInstalled
                                            ? Colors.green.withValues(
                                                alpha: 0.1,
                                              )
                                            : Colors.red.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        tool.isInstalled
                                            ? LucideIcons.circle_check
                                            : LucideIcons.circle_alert,
                                        size: 16,
                                        color: tool.isInstalled
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tool.name,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (tool.isInstalled &&
                                              tool.version != null)
                                            Text(
                                              tool.version!,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          if (tool.error != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                tool.error!,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: tool.isInstalled
                                                      ? Colors.orangeAccent
                                                      : Colors.redAccent,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
