import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/features/preview/utils/preview_cache_helper.dart';

void main() {
  group('PreviewCacheHelper', () {
    test('normalizeUrl trims and adds http scheme when missing', () {
      expect(
        PreviewCacheHelper.normalizeUrl(' 127.0.0.1:8080 '),
        'http://127.0.0.1:8080',
      );
      expect(
        PreviewCacheHelper.normalizeUrl('localhost:3000/app'),
        'http://localhost:3000/app',
      );
      expect(
        PreviewCacheHelper.normalizeUrl('https://example.com/docs'),
        'https://example.com/docs',
      );
      expect(PreviewCacheHelper.normalizeUrl('   '), '');
    });

    test('stripCacheBuster removes _qreload while preserving params and fragment', () {
      expect(
        PreviewCacheHelper.stripCacheBuster(
          'http://127.0.0.1:8080/?tab=settings&_qreload=1732260000#/home',
        ),
        'http://127.0.0.1:8080/?tab=settings#/home',
      );
      expect(
        PreviewCacheHelper.stripCacheBuster(
          'http://127.0.0.1:8080/?_qreload=1732260000#/home',
        ),
        'http://127.0.0.1:8080/#/home',
      );
      expect(
        PreviewCacheHelper.stripCacheBuster('http://127.0.0.1:8080/?_qreload=42'),
        'http://127.0.0.1:8080/',
      );
    });

    test('isLocalDevUrl detects loopback and RFC1918 hosts only', () {
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://127.0.0.1:8080')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://localhost:3000')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://0.0.0.0:8080')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://[::1]:8080')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://192.168.1.5:5173')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://10.0.2.2:8080')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://172.16.0.10:8080')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('http://172.31.255.1:8080')),
        isTrue,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('https://172.32.0.1:8080')),
        isFalse,
      );
      expect(
        PreviewCacheHelper.isLocalDevUrl(Uri.parse('https://example.com')),
        isFalse,
      );
    });

    test('buildFreshRequest attaches _qreload only on local URLs and sets no-cache headers', () {
      final localReq = PreviewCacheHelper.buildFreshRequest(
        '127.0.0.1:8080/?tab=home#/dash',
      );
      final localUri = Uri.parse(localReq.url!.rawValue);
      expect(localUri.scheme, 'http');
      expect(localUri.queryParameters['_qreload'], isNotEmpty);
      expect(localUri.queryParameters['tab'], 'home');
      expect(localUri.fragment, '/dash');
      expect(
        localReq.cachePolicy,
        URLRequestCachePolicy.RELOAD_IGNORING_LOCAL_CACHE_DATA,
      );
      expect(
        localReq.headers?['Cache-Control'],
        'no-cache, no-store, must-revalidate',
      );
      expect(localReq.headers?['Pragma'], 'no-cache');
      expect(localReq.headers?['Expires'], '0');

      final externalReq = PreviewCacheHelper.buildFreshRequest(
        'https://example.com/docs?page=1',
      );
      final externalUri = Uri.parse(externalReq.url!.rawValue);
      expect(externalUri.queryParameters.containsKey('_qreload'), isFalse);
      expect(externalUri.queryParameters['page'], '1');
      expect(
        externalReq.cachePolicy,
        URLRequestCachePolicy.RELOAD_IGNORING_LOCAL_CACHE_DATA,
      );
    });
  });
}
