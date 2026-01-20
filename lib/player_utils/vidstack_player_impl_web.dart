import 'dart:html' as html;
import 'dart:js' as js; // Needed for interop
import 'dart:async'; // Needed for Timer
import 'package:flutter/material.dart';
import 'package:hesen/player_utils/video_player_web.dart'; // Import the registry
import 'package:hesen/services/web_proxy_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // 🆕 Wake Lock

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
  html.Element? _linksContainer;

  @override
  void didUpdateWidget(VidstackPlayerImpl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url && _currentPlayer != null) {
      print('[VIDSTACK] URL updated from parent: ${widget.url}');
      final newProxiedUrl = WebProxyService.proxiedUrl(widget.url);
      _currentPlayer!.setAttribute('src', newProxiedUrl);
      _updateActiveButton(widget.url);
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // 🆕 Prevent screen sleep during playback
  }

  @override
  void dispose() {
    WakelockPlus.disable(); // 🆕 Re-enable screen sleep
    super.dispose();
  }

  void _updateActiveButton(String currentUrl) {
    if (_linksContainer == null) return;
    for (var child in _linksContainer!.children) {
      if (child is html.ButtonElement) {
        // We store the original raw URL in a data attribute for comparison
        final btnUrl = child.dataset['raw-url'];
        if (btnUrl == currentUrl) {
          child.classes.add('active');
        } else {
          child.classes.remove('active');
        }
      }
    }
  }

  int? _currentViewId;

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
              gap: 12px;
              overflow-x: auto;
              flex: 1; 
              padding: 10px 5px; /* Increased padding to prevent clipping */
              align-items: center; /* Center items vertically */
              height: 50px; /* Explicit height */
              scrollbar-width: none;
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
        String finalUrl = widget.url;
        if (finalUrl.isEmpty && widget.streamLinks.isNotEmpty) {
          finalUrl = widget.streamLinks.first['url'];
        }

        // --- التعديل الجديد هنا ---

        // إذا كان الرابط IPTV، نضيف .m3u8 يدوياً قبل البروكسي للتأكد
        if ((finalUrl.contains(':8080') || finalUrl.contains(':80')) &&
            !finalUrl.endsWith('.m3u8')) {
          finalUrl = '$finalUrl.m3u8';
        }

        // استخدام خدمة البروكسي الجديدة
        final proxiedUrl = WebProxyService.proxiedUrl(finalUrl);
        player.setAttribute('src', proxiedUrl);

        // تحديد النوع يدوياً لضمان عمل HLS
        if (finalUrl.contains('.m3u8')) {
          player.setAttribute(
              'type', 'application/x-mpegurl'); // مهم جداً للـ Vidstack
        } else if (finalUrl.contains('.mp4')) {
          player.setAttribute('type', 'video/mp4');
        }

        // الخصائص
        player.setAttribute('title', 'Live Stream');
        player.setAttribute('autoplay', 'true');
        player.setAttribute('load', 'eager');
        player.setAttribute('playsinline', 'true'); // مهم للموبايل
        player.setAttribute('crossorigin', 'anonymous');
        player.setAttribute('aspect-ratio', '16/9');
        player.setAttribute(
            'user-idle-delay', '1000'); // 🆕 Hide links faster (1s)
        player.setAttribute(
            'toggle-media-on-pointer', 'false'); // 🆕 Disable tap-to-pause

        // 5. المزود (Provider)
        final provider = html.Element.tag('media-provider');
        player.append(provider);

        // 6. 🔥 التصميم الجاهز (Layout) مع تفعيل الصور المصغرة إذا وجدت 🔥
        final layout = html.Element.tag('media-video-layout');

        // يمكنك هنا تخصيص أماكن الأزرار باستخدام slots إذا أردت تعقيداً أكثر
        // لكن التصميم الافتراضي مع الألوان المخصصة أعلاه هو الأفضل والأسرع.

        player.append(layout);

        // --- 🆕 HTML OVERLAY START ---
        final overlay = html.DivElement()..className = 'vds-overlay-header';
        // Use Unicode for back arrow to avoid SVG sanitization issues
        overlay.setInnerHtml(
          '''
            <button class="vds-back-btn">
              <span style="font-size:26px;line-height:1;display:block;color:white;">&#x276E;</span>
            </button>
            <div class="vds-links-container"></div>
          ''',
          treeSanitizer: html.NodeTreeSanitizer.trusted,
        );

        // Back Button Action
        overlay.querySelector('.vds-back-btn')!.onClick.listen((_) async {
          // 1. Exit Fullscreen
          try {
            js.JsObject.fromBrowserObject(player).callMethod('exitFullscreen');
          } catch (e) {
            print('[VIDSTACK] Error exiting fullscreen: \$e');
          }

          // 2. Return to Menu (Pop)
          await Future.delayed(const Duration(milliseconds: 100));
          if (mounted) {
            Navigator.of(context).maybePop();
          }
        });

        // 🆕 Dynamic Link Buttons Generation
        final linksContainer = overlay.querySelector('.vds-links-container')!;
        _linksContainer = linksContainer;

        for (var link in widget.streamLinks) {
          final name = link['name'] ?? 'Stream';
          final urlStr = link['url']?.toString();

          if (urlStr != null && urlStr.isNotEmpty) {
            final btn = html.ButtonElement()
              ..className = 'vds-link-btn'
              ..innerText = name;

            // 🆕 Store raw URL for reliable comparison
            btn.dataset['raw-url'] = urlStr;

            // Highlight if it's the current URL
            if (urlStr == widget.url) {
              btn.classes.add('active');
            }

            btn.onClick.listen((_) {
              print('[VIDSTACK] Switching source to: \$name');
              final newProxiedUrl = WebProxyService.proxiedUrl(urlStr);
              player.setAttribute('src', newProxiedUrl);
              player.setAttribute('autoplay', 'true');

              _updateActiveButton(urlStr);
            });

            linksContainer.append(btn);
          }
        }

        // 🆕 Force first button active if none matched (Default Selection Fix)
        if (linksContainer.children.isNotEmpty) {
          bool hasActive =
              linksContainer.children.any((c) => c.classes.contains('active'));
          if (!hasActive) {
            linksContainer.children.first.classes.add('active');
          }
        }

        player.append(overlay);
        // --- 🆕 HTML OVERLAY END ---

        // 7. أحداث (Events)
        player.addEventListener('error', (event) {
          print('[VIDSTACK] Error playing: \$proxiedUrl');
        });

        // 🆕 Resume playback after exiting fullscreen (iOS fix)
        player.addEventListener('fullscreen-change', (event) {
          final isFullscreen = player.getAttribute('fullscreen') != null;
          if (!isFullscreen) {
            // Exiting fullscreen - ensure playback continues
            js.JsObject.fromBrowserObject(player).callMethod('play');
          }
        });

        // 🆕 Mobile Auto-Hide Logic: Toggle on Tap + Auto Hide
        Timer? overlayTimer;

        void showOverlay() {
          overlay.style.opacity = '1';
          overlay.style.pointerEvents = 'auto';
          overlayTimer?.cancel();
          // Auto-hide after 4 seconds if playing
          overlayTimer = Timer(const Duration(seconds: 4), () {
            final isPaused = player.getAttribute('paused') != null;
            if (!isPaused) {
              overlay.style.opacity = '0';
              overlay.style.pointerEvents = 'none';
            }
          });
        }

        void hideOverlay() {
          overlay.style.opacity = '0';
          overlay.style.pointerEvents = 'none';
          overlayTimer?.cancel();
        }

        void toggleOverlay(html.Event event) {
          // Prevent toggling if clicking a specific button
          if (event.target is html.Element) {
            final target = event.target as html.Element;
            if (target.tagName == 'BUTTON' ||
                target.closest('button') != null) {
              return; // Let the button handle the click
            }
          }

          if (overlay.style.opacity == '0') {
            showOverlay();
          } else {
            hideOverlay();
          }
        }

        // Attach listeners for interaction
        player.addEventListener('click', (event) => toggleOverlay(event));
        player.addEventListener('touchstart', (event) {
          toggleOverlay(event);
        });

        // Mouse move just shows it (PC behavior)
        player.addEventListener('mousemove', (event) {
          if (overlay.style.opacity == '0') showOverlay();
        });

        // Initial start
        showOverlay();

        element.append(player);

        // 🆕 **FORCE PLAY** on startup to fix "First Link Not Playing"
        Future.delayed(const Duration(milliseconds: 500), () {
          try {
            js.JsObject.fromBrowserObject(player).callMethod('play');
          } catch (e) {
            print('[VIDSTACK] Auto-play failed (expected if loading): $e');
          }
        });
      },
    );
  }
}
