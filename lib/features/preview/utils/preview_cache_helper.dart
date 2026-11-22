import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Cache-busting and WebView cache-control helpers for Quantum IDE previews.
class PreviewCacheHelper {
  const PreviewCacheHelper._();

  static const String _cacheBustParam = '_qreload';

  /// Trims [rawUrl] and prepends `http://` if no HTTP(S) scheme is present.
  static String normalizeUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  /// Removes the internal `_qreload` cache-busting query parameter while keeping
  /// any other query parameters and URL fragments intact.
  static String stripCacheBuster(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.queryParametersAll.containsKey(_cacheBustParam)) {
      return rawUrl;
    }
    final remaining = Map<String, List<String>>.from(uri.queryParametersAll)
      ..remove(_cacheBustParam);
    if (remaining.isEmpty) {
      return Uri(
        scheme: uri.scheme.isEmpty ? null : uri.scheme,
        userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
        host: uri.host.isEmpty ? null : uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
        fragment: uri.hasFragment ? uri.fragment : null,
      ).toString();
    }
    return uri.replace(queryParameters: remaining).toString();
  }

  /// Returns `true` for loopback and RFC1918 local network dev hosts.
  static bool isLocalDevUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host == '[::1]') {
      return true;
    }
    if (host.startsWith('10.') || host.startsWith('192.168.')) {
      return true;
    }
    final parts = host.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]);
      if (second != null && second >= 16 && second <= 31) {
        return true;
      }
    }
    return false;
  }

  /// Builds a no-cache [URLRequest], adding a `_qreload` query timestamp for
  /// local development servers when [cacheBust] is enabled.
  static URLRequest buildFreshRequest(
    String rawUrl, {
    bool cacheBust = true,
  }) {
    final normalized = normalizeUrl(rawUrl);
    final uri = Uri.tryParse(normalized);
    String targetUrl = normalized;

    if (cacheBust && uri != null && isLocalDevUrl(uri)) {
      final params = Map<String, List<String>>.from(uri.queryParametersAll);
      params[_cacheBustParam] = [
        DateTime.now().millisecondsSinceEpoch.toString(),
      ];
      targetUrl = uri.replace(queryParameters: params).toString();
    }

    return URLRequest(
      url: WebUri(targetUrl),
      cachePolicy: URLRequestCachePolicy.RELOAD_IGNORING_LOCAL_CACHE_DATA,
      headers: const {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      },
    );
  }

  /// WebView settings configured to avoid serving stale dev bundles or SW data.
  static InAppWebViewSettings freshWebViewSettings({
    bool loadWithOverviewMode = false,
  }) {
    return InAppWebViewSettings(
      transparentBackground: true,
      javaScriptEnabled: true,
      supportZoom: true,
      useWideViewPort: true,
      loadWithOverviewMode: loadWithOverviewMode,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: true,
      disableVerticalScroll: false,
      disableHorizontalScroll: false,
      overScrollMode: OverScrollMode.ALWAYS,
      cacheEnabled: false,
      clearCache: true,
      cacheMode: CacheMode.LOAD_NO_CACHE,
    );
  }

  /// Clears native disk caches and unregisters any Service Workers / Cache API
  /// entries inside the active page.
  static Future<void> clearWebViewCaches(
    InAppWebViewController? controller,
  ) async {
    try {
      await InAppWebViewController.clearAllCache(includeDiskFiles: true);
    } catch (_) {}

    if (controller == null) return;
    try {
      await controller.evaluateJavascript(
        source: '''
(function() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations().then(function(rs) {
      rs.forEach(function(r) { r.unregister(); });
    });
  }
  if ('caches' in window) {
    caches.keys().then(function(ks) {
      ks.forEach(function(k) { caches.delete(k); });
    });
  }
})();
''',
      );
    } catch (_) {}
  }

  /// Clears caches (when [clearCache] is true) and navigates cleanly to a fresh
  /// non-cached request for [rawUrl].
  static Future<void> hardLoad(
    InAppWebViewController? controller,
    String rawUrl, {
    bool clearCache = true,
  }) async {
    if (controller == null) return;
    if (clearCache) {
      await clearWebViewCaches(controller);
    }
    try {
      await controller.loadUrl(
        urlRequest: buildFreshRequest(rawUrl, cacheBust: true),
      );
    } catch (_) {}
  }
}
