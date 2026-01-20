import 'package:flutter/foundation.dart';

class WebProxyService {
  /// Transforms a given [url] into a proxied URL if running on the Web.
  ///
  /// On Web Debug (Localhost): Uses a public proxy (https://corsproxy.io/?)
  /// On Web Release (Deployed): Uses the Vercel function (/api/proxy?url=)
  /// On Mobile: Returns the [url] as is.
  static String proxiedUrl(String url) {
    if (kIsWeb) {
      // Append cache-buster to force fresh data
      final cacheBuster = '_cb=${DateTime.now().millisecondsSinceEpoch}';
      final separator = url.contains('?') ? '&' : '?';
      final urlWithCacheBuster = '$url$separator$cacheBuster';

      if (kDebugMode) {
        // Local debugging: Return URL directly.
        // REQUIRES: Chrome with --disable-web-security
        return urlWithCacheBuster;
      } else {
        // Production: Use our own Vercel proxy for EVERYTHING to avoid Mixed Content (HTTPS vs HTTP)
        // Check if already proxied to avoid double-wrapping
        if (url.contains('/api/proxy?url=')) {
          return url;
        }
        return '/api/proxy?url=' + Uri.encodeComponent(urlWithCacheBuster);
      }
    }
    return url;
  }
}
