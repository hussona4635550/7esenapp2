import 'dart:html' as html;
import 'dart:js' as js; // Needed for interop
import 'package:flutter/material.dart';
import 'package:hesen/player_utils/video_player_web.dart'; // Import the registry
import 'package:hesen/services/web_proxy_service.dart';

class VidstackPlayerImpl extends StatefulWidget {
  final String url;
  final List<Map<String, dynamic>> streamLinks; // 🆕 Accept stream links

  const VidstackPlayerImpl({
    required this.url,
    this.streamLinks = const [], // Default to empty
    Key? key,
  }) : super(key: key);

  @override
  State<VidstackPlayerImpl> createState() => _VidstackPlayerImplState();
}

class _VidstackPlayerImplState extends State<VidstackPlayerImpl> {
  html.Element? _currentPlayer;
  int? _currentViewId;

  @override
  void didUpdateWidget(VidstackPlayerImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _updatePlayerSource();
    }
  }

  void _updatePlayerSource() {
    if (_currentPlayer != null && _currentViewId != null) {
      // استخدام البروكسي عند التحديث أيضاً
      final proxiedUrl = WebProxyService.proxiedUrl(widget.url);
      print('[VIDSTACK] Updating source to: $proxiedUrl');
      _currentPlayer!.setAttribute('src', proxiedUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      key: ValueKey(widget.url),
      viewType: 'vidstack-player',
      onPlatformViewCreated: (int viewId) {
        _currentViewId = viewId;
        final element = vidstackViews[viewId];
        if (element == null) return;

        // 1. تنظيف
        element.innerHtml = '';

        // 2. ✨ تحسين التصميم (CSS Styling) ✨
        final style = html.StyleElement();
        style.innerText = """
          /* الحاوية الرئيسية */
          .vds-player { 
            width: 100%; 
            height: 100%; 
            background-color: #000;
            overflow: hidden; /* لضمان الحواف الدائرية */
            direction: ltr !important;
            font-family: 'Cairo', sans-serif;
            
            /* 🎨 ألوان الهوية البصرية */
            --media-brand: #7C52D8; /* اللون البنفسجي للتطبيق */
            --media-focus-ring: 0 0 0 3px rgba(124, 82, 216, 0.5);
            --media-tooltip-bg: #7C52D8;
            --media-tooltip-text: #fff;
            
            /* التحكم في أحجام الأزرار */
            --media-button-size: 40px;
            --media-slider-height: 6px;
            --media-slider-thumb-size: 14px;
          }

          /* تأثير تدرج لوني خفيف على الخلفية */
          media-poster {
            background: linear-gradient(to bottom, #000, #1a1a2e);
          }

          /* تحسين شكل الأزرار عند التحويم */
          media-play-button:hover, 
          media-mute-button:hover, 
          media-fullscreen-button:hover,
          media-pip-button:hover {
            transform: scale(1.1);
            transition: transform 0.2s ease;
            background-color: rgba(255, 255, 255, 0.1);
            border-radius: 50%;
          }

          /* تحسين شريط الوقت (Slider) */
          media-time-slider {
            margin-bottom: 5px;
          }
          
            /* تكبير الأيقونات قليلاً */
            media-icon {
              width: 28px;
              height: 28px;
            }

            /* Custom Overlay Header */
            .vds-overlay-header {
              position: absolute;
              top: 0;
              left: 0;
              width: 100%;
              padding: 10px 20px;
              background: linear-gradient(to bottom, rgba(0,0,0,0.8), transparent);
              display: flex;
              align-items: center;
              z-index: 100; /* Above video */
              opacity: 0;
              transition: opacity 0.3s ease;
              pointer-events: none;
            }

            /* Show header on hover, paused, or interactions */
            .vds-player:hover .vds-overlay-header,
            .vds-player[paused] .vds-overlay-header,
            .vds-player[user-idle="false"] .vds-overlay-header {
              opacity: 1;
              pointer-events: auto;
            }

            .vds-back-btn {
              background: rgba(255, 255, 255, 0.08);
              border: 1px solid rgba(255, 255, 255, 0.15);
              border-radius: 50%;
              width: 44px;
              height: 44px;
              cursor: pointer;
              display: flex;
              align-items: center;
              justify-content: center;
              color: white;
              margin-right: 15px;
              backdrop-filter: blur(15px);
              transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
              box-shadow: 0 4px 12px rgba(0,0,0,0.4);
            }
            
            .vds-back-btn:hover {
              background: rgba(124, 82, 216, 0.4);
              border-color: rgba(124, 82, 216, 0.8);
              transform: scale(1.1);
              box-shadow: 0 0 15px rgba(124, 82, 216, 0.4);
            }
            
            .vds-back-btn svg {
              width: 26px;
              height: 26px;
              filter: drop-shadow(0 2px 4px rgba(0,0,0,0.5));
            }

            /* Container for Quality/Server Buttons */
            .vds-links-container {
              display: flex;
              gap: 10px;
              overflow-x: auto;
              margin-right: auto; /* Push to the right (RTL logic might inverse this, but flex works) */
              padding-left: 20px;
              scrollbar-width: none; /* Hide scrollbar Firefox */
            }
            .vds-links-container::-webkit-scrollbar { 
              display: none; /* Hide scrollbar Chrome/Safari */
            }

            .vds-link-btn {
              background: rgba(124, 82, 216, 0.3); /* Brand Purple Transparent */
              color: white;
              border: 1px solid rgba(255, 255, 255, 0.2);
              border-radius: 12px;
              padding: 5px 12px;
              font-family: 'Cairo', sans-serif;
              font-size: 12px;
              cursor: pointer;
              white-space: nowrap;
              transition: all 0.2s;
            }
            .vds-link-btn:hover {
              background: rgba(124, 82, 216, 0.8);
              transform: scale(1.05);
            }
            .vds-link-btn.active {
              background: #7C52D8;
              border-color: #fff;
            }
        """;
        element.append(style);

        // 3. إنشاء المشغل
        final player = html.Element.tag('media-player');
        player.className = 'vds-player';
        _currentPlayer = player;

        // 4. إعداد الرابط (مع البروكسي)
        final proxiedUrl = WebProxyService.proxiedUrl(widget.url);
        player.setAttribute('src', proxiedUrl);

        // الخصائص
        player.setAttribute('title', 'Live Stream');
        player.setAttribute('autoplay', 'true');
        player.setAttribute('load', 'eager');
        player.setAttribute('playsinline', 'true'); // مهم للموبايل
        player.setAttribute('crossorigin', 'anonymous');
        player.setAttribute('aspect-ratio', '16/9');

        // 5. المزود (Provider)
        final provider = html.Element.tag('media-provider');
        player.append(provider);

        // 6. 🔥 التصميم الجاهز (Layout) مع تفعيل الصور المصغرة إذا وجدت 🔥
        final layout = html.Element.tag('media-video-layout');

        // يمكنك هنا تخصيص أماكن الأزرار باستخدام slots إذا أردت تعقيداً أكثر
        // لكن التصميم الافتراضي مع الألوان المخصصة أعلاه هو الأفضل والأسرع.

        player.append(layout);

        // --- 🆕 HTML OVERLAY START ---
        final overlay = html.DivElement()
          ..className = 'vds-overlay-header'
          ..innerHtml = '''
            <button class="vds-back-btn">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="15 18 9 12 15 6"></polyline>
              </svg>
            </button>
            <div class="vds-links-container"></div> <!-- Container for buttons -->
          ''';

        // Back Button Action
        overlay.querySelector('.vds-back-btn')!.onClick.listen((_) async {
          // 1. Exit Fullscreen
          try {
            js.JsObject.fromBrowserObject(player).callMethod('exitFullscreen');
          } catch (e) {
            print('[VIDSTACK] Error exiting fullscreen: $e');
          }

          // 2. Return to Menu (Pop)
          await Future.delayed(const Duration(milliseconds: 100));
          if (mounted) {
            Navigator.of(context).maybePop();
          }
        });

        // 🆕 Dynamic Link Buttons Generation
        final linksContainer = overlay.querySelector('.vds-links-container')!;

        for (var link in widget.streamLinks) {
          final name = link['name'] ?? 'Stream';
          final url = link['url'];

          if (url != null && url.isNotEmpty) {
            final btn = html.ButtonElement()
              ..className = 'vds-link-btn'
              ..innerText = name;

            // Highlight if it's the current URL
            if (url == widget.url) {
              btn.classes.add('active');
            }

            btn.onClick.listen((_) {
              print('[VIDSTACK] Switching source to: $name');
              final newProxiedUrl = WebProxyService.proxiedUrl(url);
              player.setAttribute('src', newProxiedUrl);
              player.setAttribute('autoplay', 'true'); // Ensure it plays

              // Update Active State Visuals
              linksContainer.children
                  .forEach((c) => c.classes.remove('active'));
              btn.classes.add('active');
            });

            linksContainer.append(btn);
          }
        }

        player.append(overlay);
        // --- 🆕 HTML OVERLAY END ---

        // 7. أحداث (Events)
        player.addEventListener('error', (event) {
          print('[VIDSTACK] Error playing: $proxiedUrl');
        });

        element.append(player);
      },
    );
  }
}
