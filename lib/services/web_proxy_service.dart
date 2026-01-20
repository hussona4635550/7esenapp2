import 'package:flutter/foundation.dart';

class WebProxyService {
  /// Transforms a given [url] into a proxied URL if running on the Web.
  ///
  /// On Web Debug (Localhost): Uses a public proxy (https://corsproxy.io/?)
  /// On Web Release (Deployed): Uses the Vercel function (/api/proxy?url=)
  /// On Mobile: Returns the [url] as is.
  /// Transforms a given [url] into a proxied URL if running on the Web.
  static String proxiedUrl(String url) {
    if (kIsWeb) {
      // 1. إذا كان الرابط يوتيوب أو Embed، لا نستخدم بروكسي
      if (url.contains('youtube.com') ||
          url.contains('youtu.be') ||
          url.contains('ok.ru/videoembed')) {
        return url;
      }

      // 2. إصلاح روابط IPTV التي لا تنتهي بـ .m3u8
      // السيرفرات عادة تحتاج الامتداد لتعرف أننا نريد HLS وليس MPEG-TS
      if (url.contains(':8080') || url.contains(':80') || !url.contains('.')) {
        if (!url.endsWith('.m3u8')) {
          url = '$url.m3u8';
        }
      }

      // 3. استخدام CORS Proxy خارجي قوي يدعم HTTP -> HTTPS
      // هذا يحل مشكلة Mixed Content ومشكلة الـ 404
      return 'https://corsproxy.io/?' + Uri.encodeComponent(url);
    }
    return url;
  }
}
