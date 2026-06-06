import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/native_player.dart';
import 'package:cineby_tv/services/stream_servers.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
// import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MyWidget extends StatefulWidget {
  final String? url;
  final String? title;
  final int? tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final int initialProgressSeconds;
  final int? durationSeconds;
  final String? posterPath;
  final String? backdropPath;

  const MyWidget({
    super.key,
    this.url,
    this.title,
    this.tmdbId,
    this.mediaType = 'movie',
    this.seasonNumber,
    this.episodeNumber,
    this.initialProgressSeconds = 0,
    this.durationSeconds,
    this.posterPath,
    this.backdropPath,
  });

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late String _currentUrl;
  final Key _webViewKey = UniqueKey();
  bool _isLoading = true;

  // Stream extraction state
  String? _streamUrl;
  String? _subtitleUrl;
  Map<String, String> _streamHeaders = {};
  Timer? _handoffTimer;
  Timer? _autoPlayTimer;
  Timer? _extractionTimeoutTimer;
  int _autoPlayAttempts = 0;
  static const int _maxAutoPlayAttempts = 12;
  // Give the in-frame auto-clicker (up to 60s of attempts) room to surface a
  // stream before we show the manual fallback overlay.
  static const Duration _extractionTimeout = Duration(seconds: 40);
  bool _handedOff = false;
  bool _extractionFailed = false;
  bool _showRawWebview = false; // user fallback when extraction times out

  // Mirror the proven settings from the phone app (cineby-main). Notably we
  // do NOT force DESKTOP content mode or apply an iframeSandbox: both make
  // Videasy serve / restrict a different player and break stream extraction.
  late final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
    useHybridComposition: true,
    useShouldInterceptRequest: true,
  );

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url ?? serverurl;
    WakelockPlus.enable();
    _extractionTimeoutTimer = Timer(_extractionTimeout, () {
      if (!mounted || _handedOff || _streamUrl != null) return;
      setState(() => _extractionFailed = true);
    });
  }

  @override
  void dispose() {
    _handoffTimer?.cancel();
    _autoPlayTimer?.cancel();
    _extractionTimeoutTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  InAppWebViewController? _webViewController;

  bool _isAdUrl(String url) {
    const adDomains = [
      "popads",
      "monetag",
      "doubleclick",
      "adsystem",
      "popcash",
      "propellerads",
      "adsterra",
      "googlesyndication",
      "google-analytics",
      "facebook.com/tr",
      "adservice",
      "bet365",
      "1xbet",
    ];
    return adDomains.any((domain) => url.contains(domain));
  }

  bool _looksLikeStream(String lower) {
    final hasManifest = lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.mpd') ||
        lower.contains('/manifest') ||
        lower.contains('/playlist');
    if (!hasManifest) return false;
    final isSegment = lower.endsWith('.ts') ||
        lower.contains('.ts?') ||
        lower.contains('.m4s');
    return !isSegment;
  }

  bool _looksLikeSubtitle(String lower) {
    return lower.contains('.vtt') ||
        lower.contains('.srt') ||
        lower.contains('/subtitle') ||
        lower.contains('/caption');
  }

  Map<String, String> _filterHeaders(Map<String, String>? raw, Uri requestUri) {
    final out = <String, String>{};
    if (raw != null) {
      raw.forEach((k, v) {
        final lk = k.toLowerCase();
        if (lk == 'referer' ||
            lk == 'origin' ||
            lk == 'user-agent' ||
            lk == 'cookie' ||
            lk.startsWith('sec-')) {
          out[k] = v;
        }
      });
    }
    final hasReferer = out.keys.any((k) => k.toLowerCase() == 'referer');
    if (!hasReferer) {
      out['Referer'] = '${requestUri.scheme}://${requestUri.host}/';
    }
    return out;
  }

  void _captureStream(String url, Map<String, String> headers) {
    if (_handedOff) return;
    _streamUrl ??= url;
    _streamHeaders = headers;
    _scheduleHandoff();
  }

  void _captureSubtitle(String url) {
    if (_handedOff) return;
    _subtitleUrl ??= url;
  }

  void _scheduleHandoff() {
    _handoffTimer?.cancel();
    _handoffTimer = Timer(const Duration(milliseconds: 1200), _handoff);
  }

  /// Schedule an auto-tap loop that simulates a click at the centre of the
  /// webview every 1.5 s until either the stream is captured or we hit the
  /// attempt cap. This unblocks providers (like videasy) that need a user
  /// gesture before they request the manifest, even with `?play=true`.
  void _scheduleAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayAttempts = 0;
    _autoPlayTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted ||
          _handedOff ||
          _streamUrl != null ||
          _autoPlayAttempts >= _maxAutoPlayAttempts) {
        t.cancel();
        return;
      }
      _autoPlayAttempts++;
      _tapCentre();
    });
  }

  void _tapCentre() {
    _webViewController?.evaluateJavascript(source: r"""
      (function() {
        function dispatchCoordinatedClick(el) {
          if (!el) return;
          var rect = el.getBoundingClientRect();
          var x = rect.left + rect.width / 2;
          var y = rect.top + rect.height / 2;
          ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type) {
            var init = { bubbles:true, cancelable:true, view:window, clientX:x, clientY:y, buttons:1 };
            var ev = type.startsWith('pointer')
              ? new PointerEvent(type, Object.assign(init, { pointerId:1, isPrimary:true, pressure:0.5 }))
              : new MouseEvent(type, init);
            el.dispatchEvent(ev);
          });
        }
        // 1) Try to find an explicit play target.
        var selectors = [
          '.vjs-big-play-button', '.vjs-play-control',
          '.plyr__control--overlaid', '.play-button',
          '[aria-label*="Play"]', '[title*="Play"]',
          'button[aria-label*="play" i]'
        ];
        for (var i = 0; i < selectors.length; i++) {
          var el = document.querySelector(selectors[i]);
          if (el) {
            dispatchCoordinatedClick(el);
            try { el.click(); } catch(e) {}
            return;
          }
        }
        // 2) Try video element directly.
        var v = document.querySelector('video');
        if (v) {
          try { v.play(); } catch(e) {}
          dispatchCoordinatedClick(v);
        }
        // 3) Fallback: tap the geometric centre of the viewport.
        var cx = window.innerWidth / 2;
        var cy = window.innerHeight / 2;
        var elAtCentre = document.elementFromPoint(cx, cy);
        if (elAtCentre) dispatchCoordinatedClick(elAtCentre);
        // 4) Broadcast to nested iframes — the player UI often lives inside one.
        var frames = document.querySelectorAll('iframe');
        frames.forEach(function(f) {
          try {
            f.contentWindow.postMessage({ type: 'CINEBY_TAP_PLAY' }, '*');
          } catch(e) {}
        });
      })();
    """);
  }

  void _handoff() {
    if (_handedOff || _streamUrl == null || !mounted) return;
    _handedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NativePlayerPage(
          videoUrl: _streamUrl!,
          httpHeaders: _streamHeaders,
          subtitleUrl: _subtitleUrl,
          title: widget.title,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          seasonNumber: widget.seasonNumber,
          episodeNumber: widget.episodeNumber,
          initialProgressSeconds: widget.initialProgressSeconds,
          posterPath: widget.posterPath,
          backdropPath: widget.backdropPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  String? jsKey;
                  int? keyCode;

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    jsKey = 'ArrowUp'; keyCode = 38;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    jsKey = 'ArrowDown'; keyCode = 40;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    jsKey = 'ArrowLeft'; keyCode = 37;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    jsKey = 'ArrowRight'; keyCode = 39;
                  } else if (event.logicalKey == LogicalKeyboardKey.select ||
                             event.logicalKey == LogicalKeyboardKey.enter ||
                             event.logicalKey == LogicalKeyboardKey.space) {
                    jsKey = 'Enter'; keyCode = 13;
                  }

                  if (jsKey != null && _webViewController != null) {
                    _webViewController!.evaluateJavascript(
                      source: "if (window.onRemoteKey) { window.onRemoteKey('$jsKey', $keyCode); }",
                    );
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: InAppWebView(
                key: _webViewKey,
                initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
                initialSettings: settings,
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source:
                        "sessionStorage.setItem('ads-enabled-session', 'false');",
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                  // Aggressive auto-clicker — ported verbatim from the phone
                  // app (cineby-main). Runs in EVERY frame (forMainFrameOnly:
                  // false) so it reaches the nested Videasy iframe where the
                  // real <video> lives, synthesises a full pointer/click
                  // sequence at the viewport centre + offsets, hits common
                  // play-button selectors, and calls video.play() with a
                  // muted-autoplay fallback. This is what actually triggers
                  // the manifest request that shouldInterceptRequest captures.
                  UserScript(
                    forMainFrameOnly: false,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    source: r"""
                    (function() {
                      var attempts = 0;
                      var maxAttempts = 120;
                      var selectors = [
                        'button[aria-label*="play" i]',
                        'button[title*="play" i]',
                        '[role="button"][aria-label*="play" i]',
                        '[class*="play" i][class*="button" i]',
                        '[class*="bigPlay" i]',
                        '[class*="big-play" i]',
                        '[class*="playButton" i]',
                        '.plyr__control--overlaid',
                        '.vjs-big-play-button',
                        '.jw-display-icon-container',
                        '.jw-icon-display',
                        'svg[class*="play" i]',
                        'div[class*="play" i]'
                      ];
                      function fakeClick(el, x, y) {
                        if (!el) return;
                        try {
                          ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type) {
                            var ev;
                            if (type.indexOf('pointer') === 0) {
                              ev = new PointerEvent(type, {bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, pointerType: 'mouse'});
                            } else {
                              ev = new MouseEvent(type, {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0});
                            }
                            el.dispatchEvent(ev);
                          });
                          try { el.click(); } catch (e) {}
                        } catch (e) {}
                      }
                      function clickAt(x, y) {
                        var el = document.elementFromPoint(x, y);
                        fakeClick(el, x, y);
                      }
                      var timer = setInterval(function() {
                        attempts++;
                        if (attempts > maxAttempts) { clearInterval(timer); return; }
                        try {
                          var cx = (window.innerWidth || document.documentElement.clientWidth) / 2;
                          var cy = (window.innerHeight || document.documentElement.clientHeight) / 2;
                          clickAt(cx, cy);
                          clickAt(cx, cy - 40);
                          clickAt(cx, cy + 40);
                          clickAt(cx - 40, cy);
                          clickAt(cx + 40, cy);
                          for (var s = 0; s < selectors.length; s++) {
                            var els = document.querySelectorAll(selectors[s]);
                            for (var j = 0; j < els.length; j++) {
                              try { els[j].click(); } catch (e) {}
                            }
                          }
                          var videos = document.querySelectorAll('video');
                          for (var i = 0; i < videos.length; i++) {
                            var v = videos[i];
                            try {
                              var p = v.play();
                              if (p && p.catch) p.catch(function() {
                                try { v.muted = true; v.play(); } catch (e) {}
                              });
                            } catch (e) {}
                          }
                          for (var k = 0; k < videos.length; k++) {
                            if (!videos[k].paused && videos[k].currentTime > 0) {
                              clearInterval(timer);
                              return;
                            }
                          }
                        } catch (e) {}
                      }, 500);
                    })();
                  """,
                  ),
                  UserScript(
                    forMainFrameOnly: true,
                    source: r"""
                    (function() {
                      var style = document.createElement('style');
                      style.innerHTML = `
                        *:focus {
                          outline: 5px solid #2196F3 !important;
                          outline-offset: 2px !important;
                          box-shadow: 0 0 15px rgba(33, 150, 243, 0.5) !important;
                          z-index: 999999 !important;
                        }
                      `;
                      document.head.appendChild(style);

                      function triggerRemoteAction(key, keyCode) {
                        if (key === 'Enter') {
                          var target = document.activeElement;
                          var vids = document.querySelectorAll('video');
                          vids.forEach(function(v) {
                            try { if (v.paused) v.play(); else v.pause(); } catch(e) {}
                          });
                          function dispatchCoordinatedClick(el) {
                            if (!el) return;
                            var rect = el.getBoundingClientRect();
                            var x = rect.left + rect.width / 2;
                            var y = rect.top + rect.height / 2;
                            ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type) {
                              var init = { bubbles:true, cancelable:true, view:window, clientX:x, clientY:y, buttons:1 };
                              var ev = type.startsWith('pointer')
                                ? new PointerEvent(type, Object.assign(init, { pointerId:1, isPrimary:true, pressure:0.5 }))
                                : new MouseEvent(type, init);
                              el.dispatchEvent(ev);
                            });
                          }
                          function huntAndClickPlay() {
                            var selectors = [
                              '.vjs-play-control', '.plyr__control--overlaid', '.play-button',
                              '[aria-label*="Play"]', '[title*="Play"]', '.vjs-big-play-button', 'video'
                            ];
                            for (var s of selectors) {
                              var el = document.querySelector(s);
                              if (el) { dispatchCoordinatedClick(el); if (typeof el.click === 'function') el.click(); return true; }
                            }
                            return false;
                          }
                          if (target && target !== document.body) dispatchCoordinatedClick(target);
                          else huntAndClickPlay();
                        } else {
                          var vids = document.querySelectorAll('video');
                          vids.forEach(function(v) {
                            try {
                              if (key === 'ArrowLeft') v.currentTime -= 10;
                              else if (key === 'ArrowRight') v.currentTime += 10;
                              else if (key === 'ArrowUp') { v.volume = Math.min(1, v.volume + 0.1); v.muted = false; }
                              else if (key === 'ArrowDown') v.volume = Math.max(0, v.volume - 0.1);
                            } catch(e) {}
                          });
                          ['keydown','keypress','keyup'].forEach(function(t) {
                            var ev = new KeyboardEvent(t, { key:key, code:key, keyCode:keyCode, which:keyCode, bubbles:true, cancelable:true });
                            if (document.activeElement) document.activeElement.dispatchEvent(ev);
                            document.dispatchEvent(ev);
                            window.dispatchEvent(ev);
                          });
                        }
                      }

                      function broadcastAction(key, keyCode) {
                        var frames = document.querySelectorAll('iframe');
                        frames.forEach(function(f) {
                          try { f.contentWindow.postMessage({ type:'CINEBY_REMOTE_KEY', key:key, keyCode:keyCode }, '*'); } catch(e) {}
                        });
                      }

                      window.addEventListener('message', function(e) {
                        if (e.data && e.data.type === 'CINEBY_REMOTE_KEY') {
                          triggerRemoteAction(e.data.key, e.data.keyCode);
                          broadcastAction(e.data.key, e.data.keyCode);
                        }
                        if (e.data && e.data.type === 'CINEBY_TAP_PLAY') {
                          // Re-issue an Enter (treats this frame as if the user pressed OK).
                          triggerRemoteAction('Enter', 13);
                          // Also re-broadcast so deeper iframes get it.
                          var frames = document.querySelectorAll('iframe');
                          frames.forEach(function(f) {
                            try { f.contentWindow.postMessage({ type: 'CINEBY_TAP_PLAY' }, '*'); } catch(err) {}
                          });
                        }
                      });

                      window.onRemoteKey = function(key, keyCode) {
                        triggerRemoteAction(key, keyCode);
                        broadcastAction(key, keyCode);
                      };

                      function makeFocusable() {
                        var elements = document.querySelectorAll('a, button, input, select, textarea, [role="button"], video, iframe, .vjs-big-play-button, .play-button');
                        elements.forEach(function(el) {
                          if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '0');
                        });
                      }
                      makeFocusable();
                      setInterval(makeFocusable, 2000);
                    })();
                  """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                  ),
                ]),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onConsoleMessage: (controller, consoleMessage) {
                  debugPrint("WEBVIEW CONSOLE: ${consoleMessage.message}");
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;
                  if (_isAdUrl(uri.toString())) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  _currentUrl = uri.toString();
                  return NavigationActionPolicy.ALLOW;
                },
                shouldInterceptRequest: (controller, request) async {
                  final urlStr = request.url.toString();
                  if (_isAdUrl(urlStr)) {
                    return WebResourceResponse(
                        contentType: 'text/plain', statusCode: 204, data: Uint8List(0));
                  }
                  if (Platform.isAndroid && !_handedOff) {
                    final lower = urlStr.toLowerCase();
                    if (_looksLikeStream(lower)) {
                      final hdrs = _filterHeaders(request.headers, request.url);
                      _captureStream(urlStr, hdrs);
                    } else if (_looksLikeSubtitle(lower)) {
                      _captureSubtitle(urlStr);
                    }
                  }
                  return null;
                },
                onLoadStart: (controller, url) {
                  setState(() => _isLoading = true);
                },
                onLoadStop: (controller, url) {
                  setState(() => _isLoading = false);
                  _scheduleAutoPlay();
                },
              ),
            ),
            // Full-screen prep overlay. The webview keeps running underneath
            // so JS/extraction proceeds, but the user never sees its (often
            // broken-at-4K) HTML content.
            if (!_showRawWebview)
              Positioned.fill(child: _PrepOverlay(
                title: widget.title,
                backdropPath: widget.backdropPath ?? widget.posterPath,
                isLoading: _isLoading,
                streamCaptured: _streamUrl != null,
                extractionFailed: _extractionFailed,
                onRetry: _retryExtraction,
                onShowWebview: () => setState(() => _showRawWebview = true),
                onCancel: () => Navigator.of(context).maybePop(),
                onSwitchSource: _showSourcePicker,
              )),
          ],
        ),
      ),
    );
  }

  void _showSourcePicker() {
    if (widget.tmdbId == null) return;
    final current = streamServerForUrl(_currentUrl);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: kSurfaceGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.s(context)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520.s(context)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.s(context)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24.s(context), 4.s(context),
                      24.s(context), 14.s(context)),
                  child: Row(
                    children: [
                      Icon(Icons.dns_rounded,
                          color: kNetflixRed, size: 22.s(context)),
                      SizedBox(width: 10.s(context)),
                      Text(
                        'Switch source',
                        style: TextStyle(
                          color: kTextWhite,
                          fontSize: 18.s(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                for (int i = 0; i < streamServers.length; i++)
                  _SourceRow(
                    server: streamServers[i],
                    isCurrent: streamServers[i] == current,
                    autofocus: i == 0,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _switchSource(streamServers[i]);
                    },
                  ),
                SizedBox(height: 8.s(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _switchSource(StreamServer server) {
    if (widget.tmdbId == null) return;
    final newUrl = server.buildUrl(
      widget.tmdbId!,
      widget.mediaType,
      widget.seasonNumber,
      widget.episodeNumber,
    );
    // pushReplacement so the current webview + extraction state are torn
    // down and a fresh one boots on the new embed URL.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => MyWidget(
          url: newUrl,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          seasonNumber: widget.seasonNumber,
          episodeNumber: widget.episodeNumber,
          durationSeconds: widget.durationSeconds,
          initialProgressSeconds: widget.initialProgressSeconds,
          title: widget.title,
          posterPath: widget.posterPath,
          backdropPath: widget.backdropPath,
        ),
      ),
    );
  }

  void _retryExtraction() {
    setState(() {
      _extractionFailed = false;
      _streamUrl = null;
      _subtitleUrl = null;
      _streamHeaders = {};
      _autoPlayAttempts = 0;
    });
    _extractionTimeoutTimer?.cancel();
    _extractionTimeoutTimer = Timer(_extractionTimeout, () {
      if (!mounted || _handedOff || _streamUrl != null) return;
      setState(() => _extractionFailed = true);
    });
    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(_currentUrl)));
  }
}

class _PrepOverlay extends StatelessWidget {
  final String? title;
  final String? backdropPath;
  final bool isLoading;
  final bool streamCaptured;
  final bool extractionFailed;
  final VoidCallback onRetry;
  final VoidCallback onShowWebview;
  final VoidCallback onCancel;
  final VoidCallback onSwitchSource;

  const _PrepOverlay({
    required this.title,
    required this.backdropPath,
    required this.isLoading,
    required this.streamCaptured,
    required this.extractionFailed,
    required this.onRetry,
    required this.onShowWebview,
    required this.onCancel,
    required this.onSwitchSource,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop or solid black
        if (backdropPath != null)
          ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.darken),
            child: Image.network('$imgOriginal$backdropPath', fit: BoxFit.cover),
          )
        else
          Container(color: kDeepBlack),
        // Vignette
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.1,
                colors: [Colors.transparent, kDeepBlack],
                stops: [0.4, 1.0],
              ),
            ),
          ),
        ),
        Center(
          child: extractionFailed
              ? _FailureCard(
                  title: title,
                  onRetry: onRetry,
                  onShowWebview: onShowWebview,
                  onCancel: onCancel,
                )
              : _LoadingCard(
                  title: title,
                  streamCaptured: streamCaptured,
                  onSwitchSource: onSwitchSource,
                ),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String? title;
  final bool streamCaptured;
  final VoidCallback onSwitchSource;
  const _LoadingCard({
    required this.title,
    required this.streamCaptured,
    required this.onSwitchSource,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64.s(context),
          height: 64.s(context),
          child: CircularProgressIndicator(
            color: kNetflixRed,
            strokeWidth: 4.s(context).clamp(2.0, 6.0),
          ),
        ),
        SizedBox(height: 28.s(context)),
        Text(
          title ?? 'Preparing playback',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: kTextWhite,
            fontSize: 26.s(context),
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.6), blurRadius: 10.s(context)),
            ],
          ),
        ),
        SizedBox(height: 8.s(context)),
        Text(
          streamCaptured
              ? 'Loading native player…'
              : 'Extracting stream — this takes a few seconds',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14.s(context)),
        ),
        SizedBox(height: 24.s(context)),
        // Focusable switch-source button — reachable via D-pad while waiting
        // for extraction. Lets the user bail to a different provider if the
        // current one stalls without backing all the way out.
        _PillButton(
          label: 'Switch source',
          icon: Icons.dns_rounded,
          autofocus: true,
          onPressed: onSwitchSource,
        ),
      ],
    );
  }
}

class _PillButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool autofocus;
  final VoidCallback onPressed;
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: 22.s(context),
          vertical: 12.s(context),
        ),
        decoration: BoxDecoration(
          color: _focused ? kNetflixRed : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: _focused ? kNetflixRed : Colors.white.withOpacity(0.16),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, color: Colors.white, size: 18.s(context)),
            SizedBox(width: 10.s(context)),
            Text(
              widget.label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.s(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatefulWidget {
  final StreamServer server;
  final bool isCurrent;
  final bool autofocus;
  final VoidCallback onTap;
  const _SourceRow({
    required this.server,
    required this.isCurrent,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        color: _focused
            ? kNetflixRed.withOpacity(0.25)
            : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: 24.s(context),
          vertical: 14.s(context),
        ),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              color: widget.isCurrent
                  ? kNetflixRed
                  : (_focused ? Colors.white : Colors.white70),
              size: 20.s(context),
            ),
            SizedBox(width: 14.s(context)),
            Expanded(
              child: Text(
                widget.server.name,
                style: TextStyle(
                  color: widget.isCurrent
                      ? kNetflixRed
                      : kTextWhite,
                  fontSize: 14.5.s(context),
                  fontWeight: widget.isCurrent
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
            if (widget.isCurrent)
              Icon(Icons.check_rounded,
                  color: kNetflixRed, size: 18.s(context)),
          ],
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  final String? title;
  final VoidCallback onRetry;
  final VoidCallback onShowWebview;
  final VoidCallback onCancel;

  const _FailureCard({
    required this.title,
    required this.onRetry,
    required this.onShowWebview,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(32.s(context)),
      constraints: BoxConstraints(maxWidth: 560.s(context)),
      decoration: BoxDecoration(
        color: kSurfaceGrey.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12.s(context)),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: kNetflixRed, size: 48.s(context)),
          SizedBox(height: 16.s(context)),
          Text(
            'Could not auto-play',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kTextWhite,
              fontSize: 22.s(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.s(context)),
          Text(
            title != null
                ? 'We couldn\'t extract a stream for "$title" automatically.'
                : 'We couldn\'t extract a stream automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14.s(context)),
          ),
          SizedBox(height: 20.s(context)),
          Wrap(
            spacing: 10.s(context),
            runSpacing: 10.s(context),
            alignment: WrapAlignment.center,
            children: [
              _OverlayButton(
                label: 'Retry',
                icon: Icons.refresh,
                isPrimary: true,
                autofocus: true,
                onPressed: onRetry,
              ),
              _OverlayButton(
                label: 'Open web player',
                icon: Icons.open_in_browser,
                onPressed: onShowWebview,
              ),
              _OverlayButton(
                label: 'Back',
                icon: Icons.arrow_back,
                onPressed: onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool autofocus;
  final VoidCallback onPressed;

  const _OverlayButton({
    required this.label,
    required this.icon,
    this.isPrimary = false,
    this.autofocus = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal: 22.s(context),
              vertical: 12.s(context),
            ),
            decoration: BoxDecoration(
              color: isPrimary
                  ? (focused ? Colors.white : Colors.white.withOpacity(0.92))
                  : (focused ? Colors.white24 : Colors.white.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(4.s(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: 20.s(context)),
                SizedBox(width: 8.s(context)),
                Text(
                  label,
                  style: TextStyle(
                    color: isPrimary ? Colors.black : Colors.white,
                    fontSize: 14.s(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
