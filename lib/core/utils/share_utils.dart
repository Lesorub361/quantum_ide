import 'package:share_plus/share_plus.dart';
import 'dart:io';

class ShareUtils {
  static Future<void> shareFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(filePath)]));
  }

  static Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  static Future<void> shareFiles(List<String> filePaths) async {
    final files = filePaths.map((f) => XFile(f)).toList();
    await SharePlus.instance.share(ShareParams(files: files));
  }
}
