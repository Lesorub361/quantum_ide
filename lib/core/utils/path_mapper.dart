import 'package:path/path.dart' as p;
import 'dart:io';

class PathMapper {
  static const String externalBase = '/storage/emulated/0/QuantumIDE';
  static const String sdcardBase = '/sdcard/QuantumIDE';
  static const String internalGuestBase = '/root/projects';
  static const String externalGuestBase = '/root/projects/external';

  /// Maps a host path (e.g. /data/user/0/.../files/projects/my_project)
  /// to its external mirror path (e.g. /sdcard/QuantumIDE/my_project).
  static String mapToExternal(String hostPath, String appFilesDir) {
    if (!Platform.isAndroid && !Platform.isIOS) return hostPath;
    final internalHostBase = p.join(appFilesDir, 'projects');
    if (hostPath.startsWith(internalHostBase)) {
      final relative = p.relative(hostPath, from: internalHostBase);
      return p.join(externalBase, relative);
    }
    return hostPath;
  }

  /// Maps an external path or internal host path to the GUEST path (Ubuntu path).
  /// This is critical for terminal commands and build tools.
  static String mapToGuest(String path, String appFilesDir) {
    if (!Platform.isAndroid && !Platform.isIOS) return path;
    final internalHostBase = p.join(appFilesDir, 'projects');
    
    // If it's already a guest path, leave it (mostly)
    if (path.startsWith('/root') || path.startsWith('/tmp') || path.startsWith('/bin') || path.startsWith('/sdcard')) {
      return path;
    }

    // Map external path to guest path (redirect to external mount)
    if (path.startsWith(externalBase)) {
      final relative = p.relative(path, from: externalBase);
      return p.join(externalGuestBase, relative);
    }

    // Map internal host path to guest path
    if (path.startsWith(internalHostBase)) {
      final relative = p.relative(path, from: internalHostBase);
      return p.join(internalGuestBase, relative);
    }

    if (path.startsWith('/storage/emulated/0')) {
      final relative = p.relative(path, from: '/storage/emulated/0');
      return p.join('/sdcard', relative);
    }

    return path;
  }

  /// Maps a guest path (e.g. /root/projects/my_project) back to its host path.
  static String mapToHost(String guestPath, String appFilesDir, {String? activeWorkspacePath}) {
    if (!Platform.isAndroid && !Platform.isIOS) return guestPath;
    
    final internalHostBase = p.join(appFilesDir, 'projects');
    
    if (guestPath.startsWith(externalGuestBase)) {
      final relative = p.relative(guestPath, from: externalGuestBase);
      return p.join(externalBase, relative);
    }
    
    if (guestPath.startsWith(internalGuestBase)) {
      final relative = p.relative(guestPath, from: internalGuestBase);
      // Check if active workspace is external
      if (activeWorkspacePath != null && activeWorkspacePath.startsWith(externalBase)) {
        return p.join(externalBase, relative);
      }
      return p.join(internalHostBase, relative);
    }
    
    if (guestPath.startsWith('/root')) {
      final relative = p.relative(guestPath, from: '/root');
      return p.join(appFilesDir, 'rootfs', 'ubuntu', 'root', relative);
    }
    
    if (guestPath.startsWith('/tmp')) {
      final relative = p.relative(guestPath, from: '/tmp');
      return p.join(appFilesDir, 'tmp', relative);
    }
    
    if (guestPath.startsWith('/sdcard')) {
      final relative = p.relative(guestPath, from: '/sdcard');
      return p.join('/storage/emulated/0', relative);
    }
    
    if (guestPath.startsWith('/')) {
      return p.join(appFilesDir, 'rootfs', 'ubuntu', guestPath.substring(1));
    }
    
    return guestPath;
  }
}
