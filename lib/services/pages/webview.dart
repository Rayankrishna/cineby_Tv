import 'dart:collection';
import 'dart:typed_data';
import 'package:cineby_tv/services/config.dart';
// import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MyWidget extends StatefulWidget {
  final String? url;
  const MyWidget({super.key, this.url});

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // final _adBlockerWebviewController = AdBlockerWebviewController.instance;
  late String _currentUrl;
  Key _webViewKey = UniqueKey();
  bool _isLoading = true;

  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false, // BLOCKS POP-UNDERS
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
    useHybridComposition: true,
    preferredContentMode: UserPreferredContentMode.DESKTOP, // Forces desktop layout to fix 4K TV scaling
    useWideViewPort: true, // Use a wide viewport
    loadWithOverviewMode: true, // Overview mode to fit the screen
    textZoom: 100, // Prevent system font scaling issues in WebView on TV
    iframeSandbox: {
      Sandbox.ALLOW_FORMS,
      Sandbox.ALLOW_SAME_ORIGIN,
      Sandbox.ALLOW_SCRIPTS,
      Sandbox.ALLOW_DOWNLOADS,
      Sandbox.ALLOW_PRESENTATION,
    },
  );

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url ?? serverurl;
    // _initAdBlocker();
    WakelockPlus.enable();
  }

  // Future<void> _initAdBlocker() async {
  //   await _adBlockerWebviewController.initialize(
  //     FilterConfig(filterTypes: [FilterType.easyList, FilterType.adGuard]),
  //     [],
  //   );
  // }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  InAppWebViewController? _webViewController;

  bool _isAdUrl(String url) {
    final adDomains = [
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
                  debugPrint("CINEBY-REMOTE: Logical Key pressed: ${event.logicalKey.debugName}");
                  
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
                initialUrlRequest: URLRequest(url: WebUri("${_currentUrl}")),
                initialSettings: settings,
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source:
                        "sessionStorage.setItem('ads-enabled-session', 'false');",
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                  UserScript(
                    forMainFrameOnly: true,
                    source: """
                    (function() {
                      // 1. Inject Focus Styles
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

                      // 2. Local Action Handler
                      function triggerRemoteAction(key, keyCode) {
                        console.log('Cineby-TV: Action in frame:', window.location.href);
                        
                        if (key === 'Enter') {
                          var target = document.activeElement;
                          var vids = document.querySelectorAll('video');
                          
                          // A. Aggressive Video Toggle
                          vids.forEach(function(v) {
                            try {
                              if (v.paused) v.play(); else v.pause();
                            } catch(e) {}
                          });

                          // B. Coordinate-Based Click Simulation
                          function dispatchCoordinatedClick(el) {
                            if (!el) return;
                            var rect = el.getBoundingClientRect();
                            var x = rect.left + rect.width / 2;
                            var y = rect.top + rect.height / 2;
                            
                            var eventTypes = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'];
                            eventTypes.forEach(function(type) {
                              var ev;
                              var init = {
                                bubbles: true,
                                cancelable: true,
                                view: window,
                                clientX: x,
                                clientY: y,
                                buttons: 1
                              };
                              if (type.startsWith('pointer')) {
                                ev = new PointerEvent(type, Object.assign(init, { pointerId: 1, isPrimary: true, pressure: 0.5 }));
                              } else {
                                ev = new MouseEvent(type, init);
                              }
                              el.dispatchEvent(ev);
                            });
                          }

                          // C. Fallback Play Hunt
                          function huntAndClickPlay() {
                            var selectors = [
                              '.vjs-play-control', '.plyr__control--overlaid', '.play-button', 
                              '[aria-label*="Play"]', '[title*="Play"]', '.vjs-big-play-button',
                              'video'
                            ];
                            for (var s of selectors) {
                              var el = document.querySelector(s);
                              if (el) {
                                console.log('Cineby-TV: Hunt found target:', s);
                                dispatchCoordinatedClick(el);
                                if (typeof el.click === 'function') el.click();
                                return true;
                              }
                            }
                            return false;
                          }

                          if (target && target !== document.body) {
                            dispatchCoordinatedClick(target);
                          } else {
                            huntAndClickPlay();
                          }
                        } else {
                          // Robust Arrow/Key Forwarding
                          var target = document.activeElement || document;
                          
                          // A. Manual Seek & Volume Fallback
                          var vids = document.querySelectorAll('video');
                          vids.forEach(function(v) {
                            try {
                              if (key === 'ArrowLeft') {
                                v.currentTime -= 10;
                                console.log('Cineby-TV: Manual seek -10s');
                              } else if (key === 'ArrowRight') {
                                v.currentTime += 10;
                                console.log('Cineby-TV: Manual seek +10s');
                              } else if (key === 'ArrowUp') {
                                v.volume = Math.min(1, v.volume + 0.1);
                                v.muted = false;
                                console.log('Cineby-TV: Manual volume Up:', v.volume);
                              } else if (key === 'ArrowDown') {
                                v.volume = Math.max(0, v.volume - 0.1);
                                console.log('Cineby-TV: Manual volume Down:', v.volume);
                              }
                            } catch(e) {}
                          });

                          // B. Robust Event Sequence
                          ['keydown', 'keypress', 'keyup'].forEach(function(t) {
                            var ev = new KeyboardEvent(t, {
                               key: key,
                               code: key,
                               keyCode: keyCode,
                               which: keyCode,
                               bubbles: true,
                               cancelable: true
                            });
                            // Dispatch to multiple targets to be safe
                            if (document.activeElement) document.activeElement.dispatchEvent(ev);
                            document.dispatchEvent(ev);
                            window.dispatchEvent(ev);
                          });
                        }
                      }

                      // 3. Broadcast to children
                      function broadcastAction(key, keyCode) {
                        var frames = document.querySelectorAll('iframe');
                        frames.forEach(function(f) {
                          try {
                            f.contentWindow.postMessage({
                              type: 'CINEBY_REMOTE_KEY',
                              key: key,
                              keyCode: keyCode
                            }, '*');
                          } catch(e) {
                            console.error('Cineby-TV: Failed to postMessage to iframe', e);
                          }
                        });
                      }

                      // 4. Message Listeners
                      window.addEventListener('message', function(e) {
                        if (e.data && e.data.type === 'CINEBY_REMOTE_KEY') {
                          triggerRemoteAction(e.data.key, e.data.keyCode);
                          broadcastAction(e.data.key, e.data.keyCode);
                        }
                      });

                      // 5. Exposed global for Flutter (Main Frame only needs this really, but safe here)
                      window.onRemoteKey = function(key, keyCode) {
                        console.log('Cineby-TV: Root key received:', key);
                        triggerRemoteAction(key, keyCode);
                        broadcastAction(key, keyCode);
                      };

                      // 6. Make elements focusable
                      function makeFocusable() {
                        var elements = document.querySelectorAll('a, button, input, select, textarea, [role="button"], video, iframe, .vjs-big-play-button, .play-button');
                        elements.forEach(function(el) {
                          if (!el.hasAttribute('tabindex')) {
                            el.setAttribute('tabindex', '0');
                          }
                        });
                      }
                      makeFocusable();
                      setInterval(makeFocusable, 2000);
                      
                      console.log('Cineby-TV: Recursive Bridge initialized in frame:', window.location.href);
                    })();
                  """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                  ),
                ]),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onConsoleMessage: (controller, consoleMessage) {
                  debugPrint("WEBVIEW CONSOLE: \${consoleMessage.message}");
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;

                  // Lock navigation to the initial host - REMOVED for stability
                  // if (uri.host != _initialHost) {
                  //   debugPrint("Blocked cross-origin navigation: ${uri.host}");
                  //   return NavigationActionPolicy.CANCEL;
                  // }

                  if (_isAdUrl(uri.toString())) {
                    debugPrint("Blocked ad URL: $uri");
                    return NavigationActionPolicy.CANCEL;
                  }
                  // Update current valid URL
                  _currentUrl = uri.toString();
                  return NavigationActionPolicy.ALLOW;
                },
                // Optional: Intercept requests to block ad assets
                shouldInterceptRequest: (controller, request) async {
                  if (_isAdUrl(request.url.toString())) {
                    return WebResourceResponse(
                        contentType: 'text/plain', statusCode: 204, data: Uint8List(0));
                  }
                  return null;
                },
                onLoadStart: (controller, url) {
                  print("ghubgbgiusdbgiubgiuod $url");
                  setState(() {
                    _isLoading = true;
                  });
                },
                onLoadStop: (controller, url) {
                  setState(() {
                    _isLoading = false;
                  });
                },
              ),
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.blue),
              ),
          ],
        ),
      ),
    );
  }
}
