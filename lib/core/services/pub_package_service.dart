import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pub_package.dart';

class PubPackageService extends StateNotifier<AsyncValue<List<PubPackage>>> {
  final _dio = Dio();
  
  PubPackageService() : super(const AsyncValue.data([]));

  Future<void> search(String query) async {
    if (query.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    try {
      // Use pub.dev API for searching
      final response = await _dio.get('https://pub.dev/api/search?q=$query');
      final packagesList = response.data['packages'] as List;
      
      
      final List<Future<PubPackage>> detailFutures = packagesList.take(20).map((p) async {
        final name = p['package'];
        final detailResponse = await _dio.get('https://pub.dev/api/packages/$name');
        return PubPackage.fromJson({
          ...detailResponse.data,
          'name': name,
        });
      }).toList();
      
      final packageResults = await Future.wait(detailFutures);
      state = AsyncValue.data(packageResults);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final pubPackageServiceProvider = StateNotifierProvider<PubPackageService, AsyncValue<List<PubPackage>>>((ref) {
  return PubPackageService();
});
