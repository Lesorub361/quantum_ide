import 'package:path/path.dart' as p;

class FileTypeDetector {
  static const _imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico'];
  static const _svgExtensions = ['svg'];
  static const _pdfExtensions = ['pdf'];
  static const _videoExtensions = ['mp4', 'webm', 'avi', 'mov'];
  static const _audioExtensions = ['mp3', 'wav', 'ogg', 'flac', 'aac'];

  static bool isImage(String path) => _imageExtensions.contains(_ext(path));
  static bool isSvg(String path) => _svgExtensions.contains(_ext(path));
  static bool isPdf(String path) => _pdfExtensions.contains(_ext(path));
  static bool isVideo(String path) => _videoExtensions.contains(_ext(path));
  static bool isAudio(String path) => _audioExtensions.contains(_ext(path));

  static bool isPreviewable(String path) =>
      isImage(path) || isSvg(path) || isPdf(path) || isVideo(path) || isAudio(path);

  static String _ext(String path) =>
      p.extension(path).toLowerCase().replaceFirst('.', '');
}
