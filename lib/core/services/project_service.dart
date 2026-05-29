import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/project_model.dart';
import '../services/runtime_service.dart';
import '../services/workspace_service.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';

class ProjectService extends StateNotifier<List<Project>> {
  final Ref _ref;
  static const _externalPath = '/storage/emulated/0/QuantumIDE';
  StreamSubscription? _watcherSubscription;
  Timer? _syncTimer;
  
  ProjectService(Ref ref) : _ref = ref, super([]) {
    _loadAndScanProjects();
    _startFileWatcher();
    _startPeriodicSync();
  }

  @override
  void dispose() {
    _watcherSubscription?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (timer) async {
      await syncAllProjects();
    });
  }

  Future<void> syncAllProjects() async {
    final runtime = _ref.read(runtimeServiceProvider);
    final projectsDir = Directory(p.join(runtime.appDirectory, 'projects'));
    if (!await projectsDir.exists()) return;
    
    try {
      await _syncDirectory(projectsDir, Directory(_externalPath));
      await _syncApkFiles(projectsDir);
    } catch (e) {
      debugPrint('Periodic sync failed: $e');
    }
  }

  Future<void> _syncApkFiles(Directory projectsDir) async {
    try {
      await for (final projectEntity in projectsDir.list(recursive: false)) {
        if (projectEntity is Directory) {
          final name = p.basename(projectEntity.path);
          if (name == 'external') continue;
          final buildDir = Directory(p.join(projectEntity.path, 'build'));
          try {
            if (await buildDir.exists()) {
              await for (final entity in buildDir.list(recursive: true)) {
                try {
                  if (entity is File && entity.path.endsWith('.apk')) {
                    final relativePath = p.relative(entity.path, from: projectsDir.path);
                    final extPath = p.join(_externalPath, relativePath);
                    final extFile = File(extPath);
                    
                    if (!await extFile.parent.exists()) {
                      await extFile.parent.create(recursive: true);
                    }
                    
                    bool shouldCopy = false;
                    try {
                      if (!await extFile.exists()) {
                        shouldCopy = true;
                      } else {
                        final sourceTime = await entity.lastModified();
                        final destTime = await extFile.lastModified();
                        if (sourceTime.isAfter(destTime)) {
                          shouldCopy = true;
                        }
                      }
                    } catch (_) {
                      shouldCopy = true;
                    }

                    if (shouldCopy) {
                      await entity.copy(extPath);
                      debugPrint('Synced APK to phone memory: $extPath');
                    }
                  }
                } catch (e) {
                  debugPrint('Sync: Error processing APK file ${entity.path}: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('Sync: Error scanning build folder ${buildDir.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Sync: Error listing projects directory: $e');
    }
  }

  Future<void> _syncDirectory(Directory source, Directory destination) async {
    try {
      if (!await source.exists()) return;
      if (!await destination.exists()) {
        try {
          await destination.create(recursive: true);
        } catch (e) {
          debugPrint('Sync: Failed to create directory ${destination.path}: $e');
          return;
        }
      }
    } catch (e) {
      debugPrint('Sync: Failed to check source/destination: $e');
      return;
    }

    final Set<String> sourceNames = {};
    try {
      await for (final entity in source.list(recursive: false)) {
        final name = p.basename(entity.path);
        if (name == 'external') continue;
        if (name == '.git' || name == '.dart_tool' || name == '.idea' || name == '.gradle' || name == 'build' || name == 'node_modules') continue;
        sourceNames.add(name);

        final destPath = p.join(destination.path, name);
        try {
          if (entity is Directory) {
            await _syncDirectory(entity, Directory(destPath));
          } else if (entity is File) {
            // Skip symlinks as they cause FileSystemException when copied
            final isLink = await FileSystemEntity.isLink(entity.path);
            if (isLink) continue;

            final destFile = File(destPath);
            bool shouldCopy = false;
            try {
              if (!await destFile.exists()) {
                shouldCopy = true;
              } else {
                final sourceTime = await entity.lastModified();
                final destTime = await destFile.lastModified();
                if (sourceTime.isAfter(destTime)) {
                  shouldCopy = true;
                }
              }
            } catch (e) {
              shouldCopy = true; // Fallback to copy if checking fails
            }

            if (shouldCopy) {
              try {
                await entity.copy(destPath);
              } catch (e) {
                debugPrint('Sync: Failed to copy file ${entity.path} to $destPath: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('Sync: Error processing entity $name: $e');
        }
      }
    } catch (e) {
      debugPrint('Sync: Error listing directory ${source.path}: $e');
    }

    // Clean up deleted files/folders in destination
    try {
      await for (final destEntity in destination.list(recursive: false)) {
        final name = p.basename(destEntity.path);
        if (name.startsWith('.')) continue;
        if (name == 'build' || name == 'node_modules' || name == '.git' || name == '.dart_tool' || name == '.idea' || name == '.gradle') continue;

        if (destination.path == _externalPath) {
          // At the root of QuantumIDE, only delete directories representing deleted projects
          if (destEntity is Directory && !sourceNames.contains(name)) {
            try {
              await destEntity.delete(recursive: true);
            } catch (e) {
              debugPrint('Sync: Failed to delete remote project folder $name: $e');
            }
          }
        } else {
          // Inside a project folder, perform full mirror cleanup
          if (!sourceNames.contains(name)) {
            try {
              await destEntity.delete(recursive: true);
            } catch (e) {
              debugPrint('Sync: Failed to delete remote entity $name: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Sync: Error cleaning up destination ${destination.path}: $e');
    }
  }

  final Map<String, Timer> _mirrorDebouncers = {};

  void _startFileWatcher() async {
    final runtime = _ref.read(runtimeServiceProvider);
    final projectsDir = Directory(p.join(runtime.appDirectory, 'projects'));
    if (!await projectsDir.exists()) await projectsDir.create(recursive: true);

    _watcherSubscription = projectsDir.watch(recursive: true).listen((event) async {
      final path = event.path;
      // Skip noise before checking filesystem
      if (path.contains('/.dart_tool/') || 
          path.contains('/.git/') || 
          path.contains('/.idea/') ||
          path.contains('/.gradle/') ||
          path.contains('/build/') ||
          path.contains('/node_modules/')) {
        return;
      }

      if (event is FileSystemCreateEvent || event is FileSystemModifyEvent) {
        _mirrorDebouncers[path]?.cancel();
        _mirrorDebouncers[path] = Timer(const Duration(seconds: 5), () async {
          final type = await FileSystemEntity.type(path);
          if (type == FileSystemEntityType.file) {
            mirrorEntity(path);
          }
          _mirrorDebouncers.remove(path);
        });
      } else if (event is FileSystemDeleteEvent) {
        mirrorDelete(path);
      }
    });
  }

  static const _key = 'user_projects';

  Future<void> _loadAndScanProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    List<Project> savedProjects = [];
    
    if (data != null) {
      final List<dynamic> list = json.decode(data);
      savedProjects = list.map((e) => Project.fromJson(e)).toList();
    }

    // Dynamic path correction on PC: convert mobile paths to local PC paths
    if (!Platform.isAndroid && !Platform.isIOS) {
      final runtime = _ref.read(runtimeServiceProvider);
      final pcProjectsDir = p.join(runtime.appDirectory, 'projects');
      bool modified = false;
      savedProjects = savedProjects.map((proj) {
        String newPath = proj.path;
        if (proj.path.startsWith('/root/projects/')) {
          newPath = p.join(pcProjectsDir, proj.path.substring('/root/projects/'.length));
          modified = true;
        } else if (proj.path.contains('/projects/') && !proj.path.startsWith(runtime.appDirectory)) {
          final index = proj.path.indexOf('/projects/');
          newPath = p.join(pcProjectsDir, proj.path.substring(index + '/projects/'.length));
          modified = true;
        }
        if (newPath != proj.path) {
          return Project(
            id: proj.id,
            name: proj.name,
            path: newPath,
            type: proj.type,
            lastOpened: proj.lastOpened,
            iconCodePoint: proj.iconCodePoint,
            colorValue: proj.colorValue,
            iconFontFamily: proj.iconFontFamily,
            iconFontPackage: proj.iconFontPackage,
            isInternal: proj.isInternal,
            platforms: proj.platforms,
            sdkVersion: proj.sdkVersion,
          );
        }
        return proj;
      }).toList();

      if (modified) {
        await prefs.setString(_key, json.encode(savedProjects.map((e) => e.toJson()).toList()));
      }
    }

    // Scan external directory
    if (Platform.isAndroid) {
      try {
        final externalDir = Directory(_externalPath);
        if (!await externalDir.exists()) {
          await externalDir.create(recursive: true);
        }

        final List<Project> scannedProjects = [];
        final entities = await externalDir.list().toList();
        
        for (final entity in entities) {
          if (entity is Directory) {
            final path = entity.path;
            final name = p.basename(path);
            
            // Skip hidden folders
            if (name.startsWith('.')) continue;

            // Check if already in saved projects or is a mirror
            bool isAlreadyInternal = savedProjects.any((p) => p.name == name && p.isInternal);
            if (isAlreadyInternal) continue;

            // AUTOMATIC MIGRATION: If found on SD card but not internally, migrate NOW
            final runtime = _ref.read(runtimeServiceProvider);
            final internalPath = p.join(runtime.appDirectory, 'projects', name);
            
            if (!await Directory(internalPath).exists()) {
              debugPrint('Auto-migrating $name to internal storage...');
              final targetDir = Directory(internalPath);
              await targetDir.create(recursive: true);
              await _copyDirectory(entity, targetDir);
            }

            // Identify type based on files
            ProjectType type = _identifyProjectType(internalPath);

            scannedProjects.add(Project(
              id: const Uuid().v4(),
              name: name,
              path: internalPath,
              type: type,
              lastOpened: DateTime.now(),
              isInternal: true,
            ));
          }
        }

        savedProjects.addAll(scannedProjects);
      } catch (e) {
        debugPrint('Failed to scan/migrate external projects: $e');
      }
    }

    state = savedProjects;
    state.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    
    // Save the newly scanned projects if any
    final newlyScanned = state.where((p) => !savedProjects.contains(p)).toList();
    if (newlyScanned.isNotEmpty) {
      await _persistProjects();
    }
  }

  ProjectType _identifyProjectType(String path) {
    if (File(p.join(path, 'pubspec.yaml')).existsSync()) {
      return ProjectType.flutter;
    } else if (File(p.join(path, 'package.json')).existsSync()) {
      return ProjectType.nodejs;
    } else if (File(p.join(path, 'main.py')).existsSync()) {
      return ProjectType.python;
    } else if (File(p.join(path, 'index.html')).existsSync()) {
      return ProjectType.web;
    }
    return ProjectType.other;
  }

  Future<void> _persistProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(state.map((e) => e.toJson()).toList()));
  }

  Future<void> saveProject(Project project) async {
    final existingIndex = state.indexWhere((p) => p.id == project.id || p.path == project.path || (p.name == project.name && p.type == project.type));
    
    if (existingIndex >= 0) {
      state[existingIndex] = project;
      // Trigger a re-sort and UI update
      state = [...state]..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    } else {
      state = [project, ...state];
      state.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    }
    
    await _persistProjects();
  }

  Future<void> createProject({
    required String name,
    required String path,
    required ProjectType type,
    int? iconCodePoint,
    int? colorValue,
    String? iconFontFamily,
    String? iconFontPackage,
    List<String>? platforms,
    String? sdkVersion,
  }) async {
    // Validation: prevent naming project 'flutter' or 'dart'
    final normalizedName = name.toLowerCase().trim();
    if (normalizedName == 'flutter' || normalizedName == 'dart') {
      throw Exception('Project name "$name" is reserved and will cause conflicts.');
    }

    // ALWAYS use internal storage for performance and permissions
    final runtime = _ref.read(runtimeServiceProvider);
    final String finalPath = p.join(runtime.appDirectory, 'projects', name);

    final project = Project(
      id: const Uuid().v4(),
      name: name,
      path: finalPath,
      type: type,
      lastOpened: DateTime.now(),
      iconCodePoint: iconCodePoint,
      colorValue: colorValue,
      iconFontFamily: iconFontFamily,
      iconFontPackage: iconFontPackage,
      isInternal: true,
      platforms: platforms,
      sdkVersion: sdkVersion,
    );
    
    // Ensure parent directory exists
    final projectDir = Directory(finalPath);
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    await _initializeProjectFiles(finalPath, type, name, _ref, platforms: platforms, sdkVersion: sdkVersion);
    await saveProject(project);
  }

  Future<void> importProject(String path) async {
    final name = p.basename(path);
    final runtime = _ref.read(runtimeServiceProvider);
    
    // Always migrate to internal projects folder
    final String finalPath = p.join(runtime.appDirectory, 'projects', name);
    
    if (path != finalPath) {
      debugPrint('Importing/Migrating $path to $finalPath');
      final sourceDir = Directory(path);
      final targetDir = Directory(finalPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
        await _copyDirectory(sourceDir, targetDir);
      }
    }

    // Identify type based on files
    ProjectType type = _identifyProjectType(finalPath);

    final project = Project(
      id: const Uuid().v4(),
      name: name,
      path: finalPath,
      type: type,
      lastOpened: DateTime.now(),
      isInternal: true,
    );
    
    await saveProject(project);
    // Ensure it's mirrored to SD card
    await _mirrorInitialFiles(finalPath, name);
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(p.join(destination.path, p.basename(entity.path)));
        await newDirectory.create();
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  Future<void> mirrorEntity(String internalPath) async {
    final runtime = _ref.read(runtimeServiceProvider);
    final projectsPath = p.join(runtime.appDirectory, 'projects');
    
    if (!internalPath.startsWith(projectsPath)) return;
    
    try {
      final relative = p.relative(internalPath, from: projectsPath);
      final externalPath = p.join('/storage/emulated/0/QuantumIDE', relative);
      
      final type = await FileSystemEntity.type(internalPath);
      
      if (type == FileSystemEntityType.file) {
        final entity = File(internalPath);
        final extFile = File(externalPath);
        if (!await extFile.parent.exists()) await extFile.parent.create(recursive: true);
        await entity.copy(externalPath);
      } else if (type == FileSystemEntityType.directory) {
        final entity = Directory(internalPath);
        final extDir = Directory(externalPath);
        if (!await extDir.exists()) await extDir.create(recursive: true);
        
        // Recursive copy for directories asynchronously
        await for (final item in entity.list(recursive: true)) {
          if (item is File) {
            final itemRelative = p.relative(item.path, from: internalPath);
            final itemExternal = p.join(externalPath, itemRelative);
            final itemExtFile = File(itemExternal);
            if (!await itemExtFile.parent.exists()) await itemExtFile.parent.create(recursive: true);
            await item.copy(itemExternal);
          }
        }
      }
    } catch (e) {
      debugPrint('Mirroring failed: $e');
    }
  }

  Future<void> mirrorDelete(String internalPath) async {
    final runtime = _ref.read(runtimeServiceProvider);
    final projectsPath = p.join(runtime.appDirectory, 'projects');
    if (!internalPath.startsWith(projectsPath)) return;

    try {
      final relative = p.relative(internalPath, from: projectsPath);
      final externalPath = p.join('/storage/emulated/0/QuantumIDE', relative);
      
      final file = File(externalPath);
      if (await file.exists()) {
        await file.delete();
      } else {
        final dir = Directory(externalPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Mirror delete failed: $e');
    }
  }

  Future<void> _initializeProjectFiles(String path, ProjectType type, String name, Ref ref, {List<String>? platforms, String? sdkVersion}) async {
    // Check storage permission first
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }

    final runtime = ref.read(runtimeServiceProvider);
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);

    // Try to use CLI tools first if possible
    bool usedCli = false;
    try {
      if (type == ProjectType.flutter) {
        // Check if flutter executable exists inside guest rootfs
        final flutterFile = File(p.join(runtime.appDirectory, 'rootfs', 'ubuntu', 'root', 'flutter', 'bin', 'flutter'));
        if (await flutterFile.exists()) {
          // Run flutter create inside the guest container using native runCommand
          String cmd = 'flutter create --project-name ${name.replaceAll("-", "_")}';
          if (platforms != null && platforms.isNotEmpty) {
            cmd += ' --platforms ${platforms.join(",")}';
          }
          cmd += ' ${PathMapper.mapToGuest(path, runtime.appDirectory)}';
          
          await runtime.runCommand(cmd);
          // Patch Android build files to fix AGP + compileSdk compatibility
          await _patchAndroidBuildFiles(path, sdkVersion: sdkVersion);
          usedCli = true;
        }
      } else if (type == ProjectType.dart) {
        final dartFile = File(p.join(runtime.appDirectory, 'rootfs', 'ubuntu', 'root', 'flutter', 'bin', 'dart'));
        if (await dartFile.exists()) {
          // Run dart create inside the guest container using native runCommand
          final cmd = 'dart create --force ${PathMapper.mapToGuest(path, runtime.appDirectory)}';
          await runtime.runCommand(cmd);
          usedCli = true;
        }
      }
    } catch (e) {
      debugPrint('CLI Generation failed: $e, falling back to manual template');
    }

    if (usedCli) {
      await _mirrorInitialFiles(path, name);
      return;
    }

    switch (type) {
      case ProjectType.flutter:
        await _createFile(p.join(path, 'pubspec.yaml'), _flutterPubspec(name, sdkVersion: sdkVersion));
        await _createFile(p.join(path, 'lib', 'main.dart'), _flutterMain());
        await _createFile(p.join(path, 'analysis_options.yaml'), _analysisOptions());
        // Write compatible Android build files for manual template if android is selected
        if (platforms == null || platforms.isEmpty || platforms.contains('android')) {
          await _writeAndroidBuildFiles(path, name, sdkVersion: sdkVersion);
        }
        break;
      case ProjectType.dart:
        await _createFile(p.join(path, 'pubspec.yaml'), _dartPubspec(name));
        await _createFile(p.join(path, 'bin', 'main.dart'), _dartMain());
        break;
      case ProjectType.nodejs:
        await _createFile(p.join(path, 'package.json'), _nodePackage(name));
        await _createFile(p.join(path, 'index.js'), "console.log('Hello from QuantumIDE Node.js!');\n");
        break;
      case ProjectType.python:
        await _createFile(p.join(path, 'main.py'), "print('Hello from QuantumIDE Python!')\n");
        await _createFile(p.join(path, 'requirements.txt'), "");
        break;
      case ProjectType.web:
        await _createFile(p.join(path, 'index.html'), _webHtml(name));
        await _createFile(p.join(path, 'style.css'), "body { background: #0f1117; color: white; font-family: sans-serif; }\n");
        await _createFile(p.join(path, 'script.js'), "console.log('Web project loaded');\n");
        break;
      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        await _writeNativeAndroidFiles(path, name, type, sdkVersion: sdkVersion);
        break;
      default:
        await _createFile(p.join(path, 'README.md'), "# $name\nCreated with QuantumIDE\n");
    }

    // Trigger a manual mirror of these initial files
    _mirrorInitialFiles(path, name);
  }

  // ---------------------------------------------------------------------------
  // Android build file patching
  // ---------------------------------------------------------------------------

  /// Патчит Android build файлы существующего проекта (после flutter create).
  /// Устанавливает AGP 8.11.1 и compileSdk 35 чтобы избежать проблем с
  /// повреждённым android-36/android.jar.
  Future<void> _patchAndroidBuildFiles(String projectPath, {String? sdkVersion}) async {
    final sdk = sdkVersion ?? '35';
    debugPrint('[ProjectService] Patching Android build files in $projectPath with compileSdk $sdk');

    // --- android/app/build.gradle.kts ---
    final appBuildFile = File(p.join(projectPath, 'android', 'app', 'build.gradle.kts'));
    if (await appBuildFile.exists()) {
      String content = await appBuildFile.readAsString();
      // Зафиксировать compileSdk = sdk чтобы не грузить сломанный android-36
      content = content
          .replaceAll('compileSdk = flutter.compileSdkVersion', 'compileSdk = $sdk')
          .replaceAll('compileSdk = 36', 'compileSdk = $sdk')
          .replaceAll('compileSdk = 35', 'compileSdk = $sdk')
          .replaceAll('compileSdk flutter.compileSdkVersion', 'compileSdk $sdk')
          .replaceAll('compileSdkVersion 36', 'compileSdkVersion $sdk')
          .replaceAll('compileSdkVersion 35', 'compileSdkVersion $sdk')
          .replaceAll('targetSdk = flutter.targetSdkVersion', 'targetSdk = $sdk')
          .replaceAll('targetSdk = 36', 'targetSdk = $sdk')
          .replaceAll('targetSdk = 35', 'targetSdk = $sdk');
      
      // Автоматически добавить abiFilters для arm64-v8a если они отсутствуют
      if (content.contains('defaultConfig {') && !content.contains('abiFilters')) {
        content = content.replaceFirst(
          'defaultConfig {',
          'defaultConfig {\n        ndk {\n            abiFilters += listOf("arm64-v8a")\n        }',
        );
      }
      
      await appBuildFile.writeAsString(content);
      debugPrint('[ProjectService] Patched app/build.gradle.kts');
    }

    // --- android/app/build.gradle (Groovy fallback) ---
    final appBuildGroovy = File(p.join(projectPath, 'android', 'app', 'build.gradle'));
    if (await appBuildGroovy.exists()) {
      String content = await appBuildGroovy.readAsString();
      content = content
          .replaceAll('compileSdkVersion flutter.compileSdkVersion', 'compileSdkVersion $sdk')
          .replaceAll('compileSdkVersion 36', 'compileSdkVersion $sdk')
          .replaceAll('compileSdkVersion 35', 'compileSdkVersion $sdk')
          .replaceAll('compileSdk flutter.compileSdkVersion', 'compileSdk $sdk')
          .replaceAll('compileSdk 36', 'compileSdk $sdk')
          .replaceAll('compileSdk 35', 'compileSdk $sdk');
      
      if (content.contains('defaultConfig {') && !content.contains('abiFilters')) {
        content = content.replaceFirst(
          'defaultConfig {',
          'defaultConfig {\n        ndk {\n            abiFilters \x27arm64-v8a\x27\n        }',
        );
      }
      
      await appBuildGroovy.writeAsString(content);
      debugPrint('[ProjectService] Patched app/build.gradle');
    }

    // --- android/build.gradle.kts (top-level) ---
    final topBuildFile = File(p.join(projectPath, 'android', 'build.gradle.kts'));
    if (await topBuildFile.exists()) {
      String content = await topBuildFile.readAsString();
      // Обновить AGP до 8.11.1
      content = content.replaceAllMapped(
        RegExp(r'com\.android\.tools\.build:gradle:[\d.]+'),
        (_) => 'com.android.tools.build:gradle:8.11.1',
      );
      await topBuildFile.writeAsString(content);
      debugPrint('[ProjectService] Patched build.gradle.kts (top-level)');
    }

    // --- android/build.gradle (Groovy fallback) ---
    final topBuildGroovy = File(p.join(projectPath, 'android', 'build.gradle'));
    if (await topBuildGroovy.exists()) {
      String content = await topBuildGroovy.readAsString();
      content = content.replaceAllMapped(
        RegExp(r"com\.android\.tools\.build:gradle:[\d.]+"),
        (_) => "com.android.tools.build:gradle:8.11.1",
      );
      await topBuildGroovy.writeAsString(content);
      debugPrint('[ProjectService] Patched build.gradle (Groovy)');
    }

    // --- android/settings.gradle.kts ---
    final settingsFile = File(p.join(projectPath, 'android', 'settings.gradle.kts'));
    if (await settingsFile.exists()) {
      String content = await settingsFile.readAsString();
      // Обновить версию AGP плагина в секции plugins {}
      content = content.replaceAllMapped(
        RegExp(r'id\("com\.android\.application"\)\s+version\s+"[\d.]+"'),
        (_) => 'id("com.android.application") version "8.11.1"',
      );
      content = content.replaceAllMapped(
        RegExp(r'id\("com\.android\.library"\)\s+version\s+"[\d.]+"'),
        (_) => 'id("com.android.library") version "8.11.1"',
      );
      await settingsFile.writeAsString(content);
      debugPrint('[ProjectService] Patched settings.gradle.kts');
    }

    // --- android/settings.gradle (Groovy fallback) ---
    final settingsGroovy = File(p.join(projectPath, 'android', 'settings.gradle'));
    if (await settingsGroovy.exists()) {
      String groovyContent = await settingsGroovy.readAsString();
      groovyContent = groovyContent.replaceAllMapped(
        RegExp(r"id 'com\.android\.application' version '[\d.]+' apply false"),
        (_) => "id 'com.android.application' version '8.11.1' apply false",
      );
      await settingsGroovy.writeAsString(groovyContent);
      debugPrint('[ProjectService] Patched settings.gradle (Groovy)');
    }
  }

  /// Создаёт совместимые Android build файлы для ручного шаблона Flutter проекта.
  Future<void> _writeAndroidBuildFiles(String projectPath, String name, {String? sdkVersion}) async {
    final androidDir = p.join(projectPath, 'android');
    final appDir = p.join(androidDir, 'app');
    final sdk = sdkVersion ?? '35';
    final safeName = name.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    final appId = 'com.example.$safeName';
    final pkgPath = appId.replaceAll('.', '/');

    // ── settings.gradle.kts (Kotlin DSL — правильный синтаксис) ──
    await _createFile(p.join(androidDir, 'settings.gradle.kts'), """
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("\$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
rootProject.name = "$name"
""");

    // ── build.gradle.kts (top-level) ──
    await _createFile(p.join(androidDir, 'build.gradle.kts'), """
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
""");

    // ── app/build.gradle.kts ──
    await _createFile(p.join(appDir, 'build.gradle.kts'), """
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "$appId"
    compileSdk = $sdk
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "$appId"
        minSdk = 21
        targetSdk = $sdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
""");

    // ── gradle.properties ──
    await _createFile(p.join(androidDir, 'gradle.properties'), 'org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G\nandroid.useAndroidX=true\nandroid.enableJetifier=true\n');

    // ── local.properties ──
    await _createFile(p.join(androidDir, 'local.properties'), 'flutter.sdk=/root/flutter\nflutter.buildMode=debug\nflutter.versionName=1.0.0\nflutter.versionCode=1\n');

    // ── gradle/wrapper/gradle-wrapper.properties ──
    await _createFile(p.join(androidDir, 'gradle', 'wrapper', 'gradle-wrapper.properties'),
        'distributionBase=GRADLE_USER_HOME\ndistributionPath=wrapper/dists\ndistributionUrl=https\\://services.gradle.org/distributions/gradle-8.12-all.zip\nzipStoreBase=GRADLE_USER_HOME\nzipStorePath=wrapper/dists\n');

    // ── app/src/main/AndroidManifest.xml ──
    await _createFile(p.join(appDir, 'src', 'main', 'AndroidManifest.xml'), """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="$name"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
""");

    // ── app/src/debug/AndroidManifest.xml ──
    await _createFile(p.join(appDir, 'src', 'debug', 'AndroidManifest.xml'),
        '<?xml version="1.0" encoding="utf-8"?>\n<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET"/>\n</manifest>\n');

    // ── app/src/profile/AndroidManifest.xml ──
    await _createFile(p.join(appDir, 'src', 'profile', 'AndroidManifest.xml'),
        '<?xml version="1.0" encoding="utf-8"?>\n<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET"/>\n</manifest>\n');

    // ── app/src/main/res/values/strings.xml ──
    await _createFile(p.join(appDir, 'src', 'main', 'res', 'values', 'strings.xml'),
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="app_name">$name</string>\n</resources>\n');

    // ── app/src/main/res/values/styles.xml ──
    await _createFile(p.join(appDir, 'src', 'main', 'res', 'values', 'styles.xml'),
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">\n        <item name="android:windowBackground">@android:color/white</item>\n    </style>\n    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">\n        <item name="android:windowBackground">?android:colorBackground</item>\n    </style>\n</resources>\n');

    // ── app/src/main/kotlin/.../MainActivity.kt ──
    await _createFile(p.join(appDir, 'src', 'main', 'kotlin', pkgPath, 'MainActivity.kt'),
        'package $appId\n\nimport io.flutter.embedding.android.FlutterActivity\n\nclass MainActivity : FlutterActivity()\n');

    // ── .gitignore ──
    await _createFile(p.join(projectPath, '.gitignore'),
        '.dart_tool/\n.flutter-plugins\n.flutter-plugins-dependencies\n.packages\n.pub-cache/\n.pub/\nbuild/\nandroid/.gradle/\nandroid/local.properties\n*.iml\n');

    // Попытка скопировать gradlew и gradle-wrapper.jar
    await _copyGradleWrapper(androidDir);
  }

  @visibleForTesting
  Future<void> writeNativeAndroidFilesForTesting(String projectPath, String name, ProjectType type, {String? sdkVersion}) {
    return _writeNativeAndroidFiles(projectPath, name, type, sdkVersion: sdkVersion);
  }

  Future<void> _writeNativeAndroidFiles(String projectPath, String name, ProjectType type, {String? sdkVersion}) async {
    final pkg = (sdkVersion == null || sdkVersion.trim().isEmpty) 
        ? 'com.example.${name.toLowerCase().replaceAll('-', '_')}' 
        : sdkVersion.trim();
    
    final pkgPath = pkg.replaceAll('.', '/');
    final isKotlin = type == ProjectType.androidKotlin;

    // 1. root settings.gradle.kts
    await _createFile(p.join(projectPath, 'settings.gradle.kts'), '''pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "$name"
include(":app")
''');

    // 2. root build.gradle.kts
    await _createFile(p.join(projectPath, 'build.gradle.kts'), '''plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}
''');

    // 3. app/build.gradle.kts
    final pluginsBlock = isKotlin ? '''plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}''' : '''plugins {
    id("com.android.application")
}''';

    final kotlinOptionsBlock = isKotlin ? '''
    kotlinOptions {
        jvmTarget = "17"
    }''' : '';

    final dependenciesBlock = isKotlin ? '''dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}''' : '''dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}''';

    await _createFile(p.join(projectPath, 'app', 'build.gradle.kts'), '''$pluginsBlock

android {
    namespace = "$pkg"
    compileSdk = 35

    defaultConfig {
        applicationId = "$pkg"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }$kotlinOptionsBlock
}

$dependenciesBlock
''');

    // 4. app/src/main/AndroidManifest.xml
    await _createFile(p.join(projectPath, 'app', 'src', 'main', 'AndroidManifest.xml'), '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="$name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light.DarkActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
''');

    // 5. app/src/main/res/values/strings.xml
    await _createFile(p.join(projectPath, 'app', 'src', 'main', 'res', 'values', 'strings.xml'), '''<resources>
    <string name="app_name">$name</string>
</resources>
''');

    // 6. app/src/main/res/layout/activity_main.xml
    await _createFile(p.join(projectPath, 'app', 'src', 'main', 'res', 'layout', 'activity_main.xml'), '''<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Hello from Quantum IDE!"
        android:textSize="20sp"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintLeft_toLeftOf="parent"
        app:layout_constraintRight_toRightOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
''');

    // 7. MainActivity
    if (isKotlin) {
      await _createFile(p.join(projectPath, 'app', 'src', 'main', 'java', pkgPath, 'MainActivity.kt'), '''package $pkg

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
''');
    } else {
      await _createFile(p.join(projectPath, 'app', 'src', 'main', 'java', pkgPath, 'MainActivity.java'), '''package $pkg;

import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
    }
}
''');
    }

    // 8. Copy Gradle wrapper
    await _copyGradleWrapper(projectPath);
  }

  Future<void> _copyGradleWrapper(String destPath) async {
    final sourcePaths = [
      '/home/lesorub/Загрузки/quantum_ide/android',
      p.join(Directory.current.path, 'android'),
    ];

    final filesToCopy = [
      'gradlew',
      'gradlew.bat',
      'gradle/wrapper/gradle-wrapper.jar',
      'gradle/wrapper/gradle-wrapper.properties',
    ];

    bool copied = false;
    for (final srcRoot in sourcePaths) {
      bool allExist = true;
      for (final relPath in filesToCopy) {
        if (!await File(p.join(srcRoot, relPath)).exists()) {
          allExist = false;
          break;
        }
      }
      if (allExist) {
        for (final relPath in filesToCopy) {
          final srcFile = File(p.join(srcRoot, relPath));
          final destFile = File(p.join(destPath, relPath));
          await destFile.parent.create(recursive: true);
          await srcFile.copy(destFile.path);
          if (relPath == 'gradlew') {
            try {
              await Process.run('chmod', ['+x', destFile.path]);
            } catch (_) {}
          }
        }
        copied = true;
        break;
      }
    }

    if (!copied) {
      await _createFile(p.join(destPath, 'gradle/wrapper/gradle-wrapper.properties'), '''distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
''');
    }
  }


  Future<void> _mirrorInitialFiles(String internalPath, String name) async {
    // Only mirror if it's an internal project
    if (!internalPath.contains('/files/projects/')) return;
    
    try {
      final externalBase = '/storage/emulated/0/QuantumIDE/$name';
      final internalDir = Directory(internalPath);
      if (!await internalDir.exists()) return;

      await for (final entity in internalDir.list(recursive: true)) {
        if (entity is File) {
          final relative = p.relative(entity.path, from: internalPath);
          final externalPath = p.join(externalBase, relative);
          final extFile = File(externalPath);
          if (!await extFile.parent.exists()) {
            await extFile.parent.create(recursive: true);
          }
          await entity.copy(externalPath);
        }
      }
    } catch (e) {
      debugPrint('Initial mirroring failed: $e');
    }
  }

  Future<void> _createFile(String path, String content) async {
    final file = File(path);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  String _flutterPubspec(String name, {String? sdkVersion}) => '''name: $name
description: A new Flutter project.
publish_to: 'none'
version: 1.0.0+1
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.2
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0
flutter:
  uses-material-design: true
''';

  String _flutterMain() => '''import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'QuantumIDE Flutter App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  void _incrementCounter() {
    setState(() { _counter++; });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text('\$_counter', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
''';

  String _dartPubspec(String name) => '''name: $name
description: A sample command-line application.
version: 1.0.0
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  path: ^1.8.0
dev_dependencies:
  lints: ^2.0.0
  test: ^1.21.0
''';

  String _dartMain() => "void main() {\n  print('Hello from QuantumIDE Dart!');\n}\n";

  String _nodePackage(String name) => '''{
  "name": "$name",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {}
}
''';

  String _webHtml(String name) => '''<!DOCTYPE html>
<html>
<head>
    <title>$name</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <h1>$name</h1>
    <p>Created with QuantumIDE</p>
    <script src="script.js"></script>
</body>
</html>
''';

  String _analysisOptions() => "include: package:flutter_lints/analysis_options.yaml\n";

  Future<void> removeProject(String id, {bool deleteFiles = false}) async {
    final project = state.firstWhere((p) => p.id == id);
    
    // If this is the current workspace, close it
    final workspace = _ref.read(workspaceProvider);
    if (workspace.currentPath == project.path) {
      await _ref.read(workspaceProvider.notifier).closeWorkspace();
    }

    if (deleteFiles) {
      try {
        final dir = Directory(project.path);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }

        // Also delete external mirror if it exists
        if (project.path.contains('/files/projects/')) {
          final externalPath = p.join('/storage/emulated/0/QuantumIDE', project.name);
          final externalDir = Directory(externalPath);
          if (await externalDir.exists()) {
            await externalDir.delete(recursive: true);
          }
        }
      } catch (e) {
        debugPrint('Failed to delete project files: $e');
      }
    }

    state = state.where((p) => p.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(state.map((e) => e.toJson()).toList()));
  }

  void runProject(Project project, {String? targetDevice}) {
    final terminal = _ref.read(terminalTabsProvider.notifier);
    final guestPath = PathMapper.mapToGuest(project.path, _ref.read(runtimeServiceProvider).appDirectory);
    
    String command;
    switch (project.type) {
      case ProjectType.flutter:
        if (Platform.isAndroid) {
          command = 'cd "$guestPath" && flutter run -d ${targetDevice ?? "web-server --web-port 8080"}';
        } else {
          command = 'cd "$guestPath" && flutter run -d ${targetDevice ?? "linux"}';
        }
        break;
      case ProjectType.python:
        command = 'cd "$guestPath" && python3 main.py';
        break;
      case ProjectType.nodejs:
        command = 'cd "$guestPath" && node index.js';
        break;
      case ProjectType.dart:
        command = 'cd "$guestPath" && dart bin/main.dart';
        break;
      case ProjectType.shell:
        command = 'cd "$guestPath" && [ -f main.sh ] && chmod +x main.sh && ./main.sh || ls -la';
        break;
      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        command = 'cd "$guestPath" && chmod +x gradlew && ./gradlew installDebug || ./gradlew assembleDebug';
        break;
      default:
        command = 'cd "$guestPath" && ls -la';
    }
    
    terminal.sendCommand(command);
  }

  /// Публичный метод: пропатчить Android build файлы уже существующего проекта.
  /// Вызывается из UI (например, через контекстное меню проекта).
  Future<void> patchExistingProject(Project project) async {
    if (project.type != ProjectType.flutter) return;
    debugPrint('[ProjectService] Patching existing project: ${project.name}');
    await _patchAndroidBuildFiles(project.path);
  }

  /// Запустить сборку Flutter APK (debug) или Linux desktop через терминал.
  /// Перед сборкой автоматически патчит Android build файлы.
  void buildProject(Project project, {String? target}) {
    final terminal = _ref.read(terminalTabsProvider.notifier);
    final guestPath = PathMapper.mapToGuest(project.path, _ref.read(runtimeServiceProvider).appDirectory);

    if (project.type == ProjectType.flutter) {
      final buildTarget = target ?? (Platform.isAndroid ? 'apk' : 'linux');
      if (buildTarget == 'apk') {
        // Patch compileSdk inline перед сборкой (для уже существующих проектов)
        final patchCmd = [
          'cd "$guestPath"',
          // Исправить compileSdk = 36 → 35 в app/build.gradle.kts
          r"sed -i 's/compileSdk = 36/compileSdk = 35/g' android/app/build.gradle.kts 2>/dev/null || true",
          r"sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 35/g' android/app/build.gradle.kts 2>/dev/null || true",
          r"sed -i 's/targetSdk = flutter.targetSdkVersion/targetSdk = 35/g' android/app/build.gradle.kts 2>/dev/null || true",
          // Обновить AGP в settings.gradle.kts
          r'''sed -i 's/id("com.android.application") version "[0-9.]*"/id("com.android.application") version "8.11.1"/g' android/settings.gradle.kts 2>/dev/null || true''',
          // Запустить сборку
          'flutter build apk --release --no-tree-shake-icons 2>&1',
        ].join(' && ');
        terminal.sendCommand(patchCmd);
      } else {
        // Build for desktop/linux
        final buildCmd = 'cd "$guestPath" && flutter build linux --release 2>&1';
        terminal.sendCommand(buildCmd);
      }
    } else if (project.type == ProjectType.androidJava || project.type == ProjectType.androidKotlin) {
      final buildCmd = [
        'cd "$guestPath"',
        'chmod +x gradlew',
        './gradlew assembleRelease 2>&1',
      ].join(' && ');
      terminal.sendCommand(buildCmd);
    } else {
      runProject(project);
    }
  }
}

final projectServiceProvider = StateNotifierProvider<ProjectService, List<Project>>((Ref ref) {
  return ProjectService(ref);
});

