import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HfModelItem {
  final String id;
  final String name;
  final String author;
  final int downloads;
  final int likes;
  final List<String> tags;
  final String? pipelineTag;

  const HfModelItem({
    required this.id,
    required this.name,
    required this.author,
    required this.downloads,
    required this.likes,
    required this.tags,
    this.pipelineTag,
  });

  factory HfModelItem.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['modelId']?.toString() ?? '';
    final parts = id.split('/');
    final author = parts.length > 1 ? parts[0] : 'community';
    final name = parts.length > 1 ? parts.sublist(1).join('/') : id;

    final rawTags = json['tags'];
    final tagsList = rawTags is List ? rawTags.map((e) => e.toString()).toList() : <String>[];

    return HfModelItem(
      id: id,
      name: name,
      author: author,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      tags: tagsList,
      pipelineTag: json['pipeline_tag']?.toString(),
    );
  }
}

class HfGgufFile {
  final String filename;
  final int sizeBytes;
  final String sizeFormatted;
  final String quantization;
  final String downloadUrl;

  const HfGgufFile({
    required this.filename,
    required this.sizeBytes,
    required this.sizeFormatted,
    required this.quantization,
    required this.downloadUrl,
  });

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String deduceQuant(String filename) {
    final upper = filename.toUpperCase();
    final regex = RegExp(r'(Q\d_[A-Z0-9_]+|IQ\d_[A-Z0-9_]+|FP16|BF16|F16|F32|Q4_K_M|Q4_K_S|Q5_K_M|Q8_0)');
    final match = regex.firstMatch(upper);
    return match?.group(0) ?? 'GGUF';
  }
}

class HuggingFaceHubService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  Future<List<HfModelItem>> searchGgufModels(String query, {int limit = 25, String sort = 'downloads'}) async {
    final cleanQuery = query.trim().replaceAll(' ', '+');
    final url = cleanQuery.isEmpty
        ? 'https://huggingface.co/api/models?filter=gguf&sort=downloads&direction=-1&limit=$limit'
        : 'https://huggingface.co/api/models?search=$cleanQuery+gguf&sort=$sort&direction=-1&limit=$limit';

    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => HfModelItem.fromJson(item as Map<String, dynamic>))
            .where((m) => m.id.isNotEmpty)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<HfGgufFile>> fetchRepoGgufFiles(String repoId) async {
    final url = 'https://huggingface.co/api/models/$repoId/tree/main';
    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data is List) {
        final list = <HfGgufFile>[];
        for (final item in response.data as List) {
          if (item is Map) {
            final path = item['path']?.toString() ?? '';
            final type = item['type']?.toString();
            if (type == 'file' && path.toLowerCase().endsWith('.gguf')) {
              final size = (item['size'] as num?)?.toInt() ?? 0;
              final quant = HfGgufFile.deduceQuant(path);
              final downloadUrl = 'https://huggingface.co/$repoId/resolve/main/$path';
              list.add(HfGgufFile(
                filename: path,
                sizeBytes: size,
                sizeFormatted: HfGgufFile.formatBytes(size),
                quantization: quant,
                downloadUrl: downloadUrl,
              ));
            }
          }
        }
        // Sort files: Q4_K_M first (best for mobile), then by size ascending
        list.sort((a, b) {
          if (a.quantization.contains('Q4_K_M') && !b.quantization.contains('Q4_K_M')) return -1;
          if (!a.quantization.contains('Q4_K_M') && b.quantization.contains('Q4_K_M')) return 1;
          return a.sizeBytes.compareTo(b.sizeBytes);
        });
        return list;
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}

final huggingFaceHubServiceProvider = Provider<HuggingFaceHubService>((ref) {
  return HuggingFaceHubService();
});
