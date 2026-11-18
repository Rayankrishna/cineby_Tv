import 'dart:async';

import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/webview.dart';
import 'package:cineby_tv/services/stream_servers.dart';
import 'package:cineby_tv/services/subtitle_service.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class NativePlayerPage extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> httpHeaders;
  final String? subtitleUrl;

  /// Which provider this stream came from, for the Source picker's tick.
  final String? sourceName;
  final String? imdbId; // for subtitle lookup (YIFY + OpenSubtitles)
  final String? title;
  final int? tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final int initialProgressSeconds;
  final int? durationSeconds;
  final String? posterPath;
  final String? backdropPath;

  const NativePlayerPage({
    super.key,
    required this.videoUrl,
    this.httpHeaders = const {},
    this.subtitleUrl,
    this.sourceName,
    this.imdbId,
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
  State<NativePlayerPage> createState() => _NativePlayerPageState();
}

class _NativePlayerPageState extends State<NativePlayerPage> {
  late VideoPlayerController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _initialized = false;
  bool _showControls = true;
  bool _showSubtitles = true;
  // English-by-default tracks: YIFY (movies) + OpenSubtitles (movies + TV),
  // by IMDb id. Best-ranked first; the first is auto-selected as the default.
  List<SubtitleTrack> _subTracks = [];
  // Active subtitle key: captured URL OR a SubtitleTrack.key. null = Off.
  String? _activeSubKey;
  // True once the user manually picks a track, so the async English
  // auto-select doesn't override their choice.
  bool _userPickedSub = false;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _hideTimer;
  Timer? _progressTimer;
  DateTime? _streamExtractedAt;

  // True once we've pushReplacement'd to a fresh webview for a source switch.
  // Guards dispose() from releasing the wakelock the new page just took.
  bool _switchingSource = false;

  /// Subtitles/Source dropdown anchored above the control bar.
  bool _optionsOpen = false;

  /// The provider the user pinned, null = Auto. Distinct from
  /// [NativePlayerPage.sourceName], which is whichever provider actually won
  /// and is now playing — in Auto those differ every time.
  String? _pinnedSourceName;

  /// While LEFT/RIGHT is held, the absolute position the user is scrubbing
  /// towards. Each repeat moves this, and only the final value is committed —
  /// issuing a seekTo per repeat (~20/s) stalls the decoder.
  Duration? _seekTarget;
  Timer? _seekCommit;
  /// Shortest gap between seek steps while an arrow is held. Android repeats
  /// ~20x/s; at 10s a step that scrubs ~200s of content per second held,
  /// which overshoots wildly. Pacing it keeps a hold aimable.
  static const int _seekRepeatGapMs = 150;
  final Stopwatch _seekClock = Stopwatch()..start();
  int _lastSeekRepeatMs = -1000;

  // Seek indicator
  String? _seekHint;
  Timer? _seekHintTimer;

  /// HOME / app-switch handling. Disposed alongside the timers.
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _streamExtractedAt = DateTime.now();
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initController();
    // Only the "no longer visible" callbacks: `inactive` also fires for
    // transient overlays that never backgrounded the app, and pausing on
    // those would be its own hiccup.
    _lifecycle = AppLifecycleListener(
      onHide: _handleBackgrounded,
      onPause: _handleBackgrounded,
      onShow: () {
        if (mounted) _revealControls();
      },
    );
    _scheduleHideControls();
    loadSelectedServer().then((server) {
      if (mounted) setState(() => _pinnedSourceName = server?.name);
    });
  }

  Future<void> _initController() async {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      httpHeaders: widget.httpHeaders,
    );

    try {
      await _controller.initialize();
      if (widget.initialProgressSeconds > 0) {
        await _controller.seekTo(
          Duration(seconds: widget.initialProgressSeconds),
        );
      }
      await _controller.play();

      if (widget.subtitleUrl != null && widget.subtitleUrl!.isNotEmpty) {
        await _loadSubtitles(widget.subtitleUrl!, userInitiated: false);
      }

      _controller.addListener(_handleVideoError);

      _progressTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _saveProgress(),
      );

      if (mounted) {
        setState(() {
          _initialized = true;
        });
        _focusNode.requestFocus();
        // Fetch English subtitles (YIFY + OpenSubtitles) in the background and
        // auto-select the best as the default.
        _loadSubtitleTracks();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
        _focusErrorView();
      }
    }
  }

  /// `autofocus` alone cannot do this: the route's scope already has a
  /// focused child (this page's root node), and Flutter only applies an
  /// autofocus when the enclosing scope has none. Without this the error
  /// buttons render with no ring and the first press goes nowhere.
  void _focusErrorView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasError) return;
      for (final node in _focusNode.traversalDescendants) {
        if (node.canRequestFocus) {
          node.requestFocus();
          return;
        }
      }
    });
  }

  void _handleVideoError() {
    if (!mounted) return;
    if (_controller.value.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = _controller.value.errorDescription;
      });
      _focusErrorView();
    }
  }

  /// Load a captured iframe subtitle URL (.srt or .vtt → normalised to VTT).
  Future<void> _loadSubtitles(String url, {bool userInitiated = true}) async {
    if (userInitiated) _userPickedSub = true;
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: widget.httpHeaders,
      );
      if (response.statusCode == 200) {
        final body = response.body;
        // A captured "subtitle" URL is often an HTML page or non-subtitle
        // resource — never feed that to the caption parser.
        if (looksLikeHtml(body) ||
            (!body.contains('-->') && !body.trimLeft().startsWith('WEBVTT'))) {
          return;
        }
        final vtt =
            body.trimLeft().startsWith('WEBVTT')
                ? body
                : SubtitleService.instance.srtToVtt(body);
        await _controller.setClosedCaptionFile(
          Future.value(WebVTTCaptionFile(vtt)),
        );
        if (mounted) {
          setState(() {
            _activeSubKey = url;
            _showSubtitles = true;
          });
        }
      }
    } catch (_) {
      // Subtitle load failed — keep playing without them.
    }
  }

  /// Select a fetched subtitle track (YIFY or OpenSubtitles): resolve it to
  /// WebVTT via the service and apply it.
  Future<void> _setTrack(SubtitleTrack t, {bool userInitiated = true}) async {
    if (userInitiated) _userPickedSub = true;
    setState(() {
      _activeSubKey = t.key;
      _showSubtitles = true;
    });
    final vtt = await SubtitleService.instance.vttForTrack(t);
    if (vtt != null && mounted) {
      await _controller.setClosedCaptionFile(
        Future.value(WebVTTCaptionFile(vtt)),
      );
    }
  }

  /// Turn subtitles off (clear the caption track).
  Future<void> _clearSubtitles({bool userInitiated = true}) async {
    if (userInitiated) _userPickedSub = true;
    setState(() {
      _activeSubKey = null;
      _showSubtitles = false;
    });
    await _controller.setClosedCaptionFile(
      Future.value(WebVTTCaptionFile('WEBVTT\n\n')),
    );
  }

  /// Fetch English subtitle tracks — YIFY for movies, OpenSubtitles for movies
  /// and TV episodes (by IMDb id from the detail response) — and auto-select
  /// the best as default (unless the user already chose a track).
  Future<void> _loadSubtitleTracks() async {
    final id = widget.tmdbId;
    final imdb = widget.imdbId;
    if ((imdb == null || imdb.isEmpty) && id == null) return;
    final tracks = await SubtitleService.instance.englishTracks(
      imdbId: imdb,
      tmdbId: id,
      mediaType: widget.mediaType,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
    );
    debugPrint(
      '[SUBS] player: ${tracks.length} english tracks '
      '(imdb=$imdb tmdb=$id s=${widget.seasonNumber} e=${widget.episodeNumber})',
    );
    if (!mounted || tracks.isEmpty) return;
    setState(() => _subTracks = tracks);
    if (!_userPickedSub) {
      await _setTrack(tracks.first, userInitiated: false);
    }
  }

  Future<void> _saveProgress() async {
    if (widget.tmdbId == null) return;
    if (!_controller.value.isInitialized) return;
    final pos = _controller.value.position.inSeconds;
    final dur = _controller.value.duration.inSeconds;
    if (pos <= 0) return;
    await historyStore.record(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
      progressSeconds: pos,
      durationSeconds: dur > 0 ? dur : widget.durationSeconds,
      title: widget.title,
      posterPath: widget.posterPath,
      backdropPath: widget.backdropPath,
    );
  }

  // HOME / app-switch mid-film: ExoPlayer has no lifecycle handling of its
  // own, so without this the audio keeps playing over the TV launcher and the
  // 10s progress timer keeps writing a position that runs ahead of what the
  // user actually watched. Deliberately no auto-resume on the way back —
  // Netflix and Apple TV both return paused.
  void _handleBackgrounded() {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) _controller.pause();
    _saveProgress();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    // Keep the scrubber, clock and centre play glyph up while paused, the way
    // Netflix and Apple TV do — a bare frozen frame reads as a dead stream.
    if (_initialized && !_controller.value.isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _revealControls() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _scheduleHideControls();
  }

  void _flashSeekHint(String text) {
    setState(() => _seekHint = text);
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _seekBy(int seconds) {
    if (!_controller.value.isInitialized) return;
    final total = _controller.value.duration;
    // Chain off the pending target, not the decoder's position, so a held
    // key accumulates predictably instead of racing the (lagging) playhead.
    final base = _seekTarget ?? _controller.value.position;
    var target = base + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    setState(() => _seekTarget = target);
    final delta = target - _controller.value.position;
    // Leading sign is load-bearing: the hint's slide direction keys off it.
    _flashSeekHint(
      '${delta.isNegative ? '-' : '+'}${_fmt(delta.abs())}   ${_fmt(target)}',
    );
    _revealControls();
    _seekCommit?.cancel();
    _seekCommit = Timer(const Duration(milliseconds: 260), _commitSeek);
  }

  Future<void> _commitSeek() async {
    final target = _seekTarget;
    if (target == null || !mounted) return;
    await _controller.seekTo(target);
    // A repeat can land while seekTo is still in flight (network seeks
    // routinely outlast the debounce). It has already moved _seekTarget and
    // armed a fresh timer, so clearing unconditionally would drop it.
    if (mounted && _seekTarget == target) {
      setState(() => _seekTarget = null);
    }
  }

  Future<void> _togglePlayPause() async {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
    _revealControls();
  }

  Future<void> _play() async {
    if (!_controller.value.isPlaying) await _controller.play();
    _revealControls();
  }

  Future<void> _pause() async {
    if (_controller.value.isPlaying) await _controller.pause();
    _revealControls();
  }

  void _toggleSubtitles() {
    // Toggle between Off and the best available track (fetched English first,
    // else the captured iframe sub).
    if (_showSubtitles && _activeSubKey != null) {
      _clearSubtitles();
    } else if (_subTracks.isNotEmpty) {
      _setTrack(_subTracks.first);
    } else if (widget.subtitleUrl != null && widget.subtitleUrl!.isNotEmpty) {
      _loadSubtitles(widget.subtitleUrl!);
    } else {
      setState(() => _showSubtitles = !_showSubtitles);
    }
    _revealControls();
  }

  bool _streamLikelyExpired() {
    final ts = _streamExtractedAt;
    if (ts == null) return false;
    return DateTime.now().difference(ts).inSeconds > 30;
  }

  // A held key auto-repeats ~20x/s. Only seeking should act on every repeat;
  // every other key behaves like TvFocusable._onKeyEvent — the repeat is
  // swallowed so it can't leak into traversal, but the action doesn't re-fire.
  // Not `const`: LogicalKeyboardKey overrides ==, so a const Set of them is a
  // compile-time error.
  static final Set<LogicalKeyboardKey> _repeatableKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.mediaFastForward,
    LogicalKeyboardKey.mediaRewind,
    LogicalKeyboardKey.mediaTrackNext,
    LogicalKeyboardKey.mediaTrackPrevious,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // The error view owns the D-pad: its buttons are real focus nodes, so
    // arrows must reach the traversal policy and OK must reach the focused
    // button rather than toggling a dead controller. Must precede every
    // other branch, or the buttons stay decorative.
    if (_hasError) return KeyEventResult.ignored;
    // While the dropdown is open every key belongs to it: this handler sits
    // above the panel in the tree, so swallowing arrows here would both seek
    // the video and stop focus from moving between the options.
    if (_optionsOpen) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (event is KeyRepeatEvent && !_repeatableKeys.contains(key)) {
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyRepeatEvent) {
        final now = _seekClock.elapsedMilliseconds;
        if (now - _lastSeekRepeatMs < _seekRepeatGapMs) {
          return KeyEventResult.handled;
        }
        _lastSeekRepeatMs = now;
      }
      _seekBy(key == LogicalKeyboardKey.arrowLeft ? -10 : 10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // Open the Subtitles/Source dropdown so remotes without a 'C' key or
      // media-stop button can still reach the subtitle control.
      _openOptions();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _revealControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      _play();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      _pause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      _seekBy(60);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      _seekBy(-60);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      // Keyboard ESC only (dev/testing). The hardware BACK button (goBack) is
      // handled by Flutter's back dispatcher — popping here too double-pops
      // (player → details → home), skipping the details page. Let the
      // framework pop once; dispose() still saves progress on the way out.
      _saveProgress();
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.mediaStop) {
      _toggleSubtitles();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _saveProgress();
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _seekHintTimer?.cancel();
    _seekCommit?.cancel();
    _lifecycle?.dispose();
    _controller.removeListener(_handleVideoError);
    _controller.dispose();
    _focusNode.dispose();
    // Don't release the wakelock if we're handing off to a fresh webview for a
    // source switch — it has already re-enabled it and this dispose runs after.
    if (!_switchingSource) {
      WakelockPlus.disable();
    }
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ============== OPTIONS DROPDOWN ==============

  /// Opens the Subtitles/Source dropdown anchored above the control bar.
  /// Playback deliberately keeps running underneath — this is a small panel,
  /// not a modal, so the user can see the effect of a subtitle change live.
  void _openOptions() {
    // The panel only renders once the stream is up; latching the flag before
    // that swallows every key with nothing on screen to receive them.
    if (_optionsOpen || !_initialized || _hasError) return;
    _hideTimer?.cancel(); // keep the bar up while the panel is anchored to it
    setState(() {
      _showControls = true;
      _optionsOpen = true;
    });
  }

  void _closeOptions() {
    if (!_optionsOpen) return;
    setState(() => _optionsOpen = false);
    _focusNode.requestFocus();
    _scheduleHideControls();
  }

  /// [server] null = Auto (race every provider), which is the default.
  Future<void> _switchSource(StreamServer? server) async {
    if (widget.tmdbId == null) return;
    // Remember the pick so the next title starts on it too. Previously this
    // choice lived only in the pushed URL — which MyWidget ignores — so the
    // picker had no effect at all.
    await saveSelectedServer(server);
    if (!mounted) return;
    _switchingSource = true;
    _saveProgress();
    // pushReplacement to MyWidget — fresh webview boots, extracts on the
    // chosen provider, and lands back in NativePlayerPage. Current progress
    // carries over via initialProgressSeconds so playback resumes near where
    // the user was.
    final resumeSeconds = _controller.value.position.inSeconds;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder:
            (_, __, ___) => MyWidget(
              forcedServer: server,
              imdbId: widget.imdbId,
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              seasonNumber: widget.seasonNumber,
              episodeNumber: widget.episodeNumber,
              durationSeconds: widget.durationSeconds,
              initialProgressSeconds:
                  resumeSeconds > 0
                      ? resumeSeconds
                      : widget.initialProgressSeconds,
              title: widget.title,
              posterPath: widget.posterPath,
              backdropPath: widget.backdropPath,
            ),
      ),
    );
  }

  /// Error-view recovery: the stream URL is dead (expired, most often), so go
  /// back through a fresh extraction instead of just closing the player. Same
  /// handoff as [_switchSource], minus the pin — MyWidget falls back to the
  /// saved choice and then to a full race.
  void _reExtract() {
    if (widget.tmdbId == null) return;
    // Hand the wakelock to the fresh webview; dispose() runs after its
    // initState has already re-enabled it.
    _switchingSource = true;
    final resumeSeconds =
        _controller.value.isInitialized
            ? _controller.value.position.inSeconds
            : 0;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder:
            (_, __, ___) => MyWidget(
              imdbId: widget.imdbId,
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              seasonNumber: widget.seasonNumber,
              episodeNumber: widget.episodeNumber,
              durationSeconds: widget.durationSeconds,
              initialProgressSeconds:
                  resumeSeconds > 0
                      ? resumeSeconds
                      : widget.initialProgressSeconds,
              title: widget.title,
              posterPath: widget.posterPath,
              backdropPath: widget.backdropPath,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // BACK dismisses the dropdown first and only then leaves the player.
      canPop: !_optionsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeOptions();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_initialized && !_hasError)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                )
              else if (_hasError)
                _buildErrorView(context)
              else
                const Center(
                  child: CircularProgressIndicator(color: kNetflixRed),
                ),

              if (_initialized && !_hasError && _showSubtitles)
                _buildCaption(context),

              if (_initialized && !_hasError)
                AnimatedSwitcher(
                  duration: TvMotion.focus,
                  child:
                      _seekHint == null
                          ? const SizedBox.shrink()
                          : KeyedSubtree(
                            key: ValueKey(_seekHint!.startsWith('-')),
                            child: _buildSeekHint(context),
                          ),
                ),

              // Controls fade in and out rather than popping on every key.
              if (_initialized && !_hasError)
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1 : 0,
                    duration: TvMotion.fade,
                    curve: TvMotion.curve,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (_, __, ___) => _buildControls(context),
                    ),
                  ),
                ),

              // Subtitles / Source dropdown, anchored to the bar it belongs
              // to instead of taking over the screen.
              if (_initialized && !_hasError && _optionsOpen)
                _OptionsPanel(
                  tracks: _subTracks,
                  activeSubKey: _activeSubKey,
                  embeddedUrl: widget.subtitleUrl,
                  pinnedSourceName: _pinnedSourceName,
                  playingSourceName: widget.sourceName,
                  onOff: _clearSubtitles,
                  onTrack: _setTrack,
                  onEmbedded: () => _loadSubtitles(widget.subtitleUrl!),
                  onSource: (s) {
                    _closeOptions();
                    _switchSource(s);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaption(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (_, value, __) {
        final text = value.caption.text;
        if (text.isEmpty) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: 80.s(context),
          // Cap at the broadcast title-safe width so a long cue wraps inside
          // the panel instead of running edge to edge into TV overscan. No
          // maxLines: clipping a line of dialogue is worse than a wide bar.
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.8,
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.s(context),
                  vertical: 6.s(context),
                ),
                color: Colors.black54,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22.s(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeekHint(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: 28.s(context),
          vertical: 16.s(context),
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12.s(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _seekHint!.startsWith('-')
                  ? Icons.fast_rewind
                  : Icons.fast_forward,
              color: Colors.white,
              size: 36.s(context),
            ),
            SizedBox(width: 12.s(context)),
            Text(
              _seekHint!,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28.s(context),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final value = _controller.value;
    // Show where the user is scrubbing to, not where the decoder still is.
    final position = _seekTarget ?? value.position;
    final duration = value.duration;
    final progress =
        duration.inMilliseconds == 0
            ? 0.0
            : position.inMilliseconds / duration.inMilliseconds;
    // How far the stream has downloaded ahead of the playhead.
    final bufferedEnd =
        value.buffered.isEmpty ? Duration.zero : value.buffered.last.end;
    final buffered =
        duration.inMilliseconds == 0
            ? 0.0
            : bufferedEnd.inMilliseconds / duration.inMilliseconds;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
          stops: const [0, 0.25, 0.75, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Title + back hint
          Positioned(
            top: 24.s(context),
            left: 32.s(context),
            right: 32.s(context),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 24.s(context),
                ),
                SizedBox(width: 8.s(context)),
                Text(
                  'Back',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14.s(context),
                  ),
                ),
                const Spacer(),
                if (widget.title != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title!,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.s(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Which episode is playing, for series.
                      if (widget.seasonNumber != null &&
                          widget.episodeNumber != null)
                        Padding(
                          padding: EdgeInsets.only(top: 2.s(context)),
                          child: Text(
                            'S${widget.seasonNumber} · E${widget.episodeNumber}',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12.s(context),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          // Centre glyph: buffering spinner while the stream catches up,
          // otherwise the paused indicator.
          Center(
            child:
                value.isBuffering
                    ? SizedBox(
                      width: 48.s(context),
                      height: 48.s(context),
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                    : AnimatedOpacity(
                      opacity: value.isPlaying ? 0 : 1,
                      duration: TvMotion.focus,
                      curve: TvMotion.curve,
                      child: Icon(
                        Icons.play_circle,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 84.s(context),
                      ),
                    ),
          ),
          // Bottom seek bar + times
          Positioned(
            left: 32.s(context),
            right: 32.s(context),
            bottom: 32.s(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 12.s(context),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final knob = 12.s(context);
                      final track = 4.s(context);
                      final played =
                          constraints.maxWidth * progress.clamp(0.0, 1.0);
                      return Stack(
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: track,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(track),
                            ),
                          ),
                          // Downloaded-ahead region, so a stall reads as
                          // "still buffering" rather than "frozen".
                          Container(
                            height: track,
                            width:
                                constraints.maxWidth * buffered.clamp(0.0, 1.0),
                            decoration: BoxDecoration(
                              color: Colors.white38,
                              borderRadius: BorderRadius.circular(track),
                            ),
                          ),
                          Container(
                            height: track,
                            width: played,
                            decoration: BoxDecoration(
                              color: kNetflixRed,
                              borderRadius: BorderRadius.circular(track),
                            ),
                          ),
                          Positioned(
                            left: (played - knob / 2).clamp(
                              0.0,
                              constraints.maxWidth - knob,
                            ),
                            child: Container(
                              width: knob,
                              height: knob,
                              decoration: const BoxDecoration(
                                color: kNetflixRed,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(height: 8.s(context)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(position),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.s(context),
                      ),
                    ),
                    // Reads as a button and names the provider in play, so
                    // the source is knowable without opening anything.
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.s(context),
                        vertical: 4.s(context),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: Colors.white,
                            size: 15.s(context),
                          ),
                          SizedBox(width: 4.s(context)),
                          Text(
                            'Options',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.s(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8.s(context)),
                          Icon(
                            _showSubtitles
                                ? Icons.closed_caption_rounded
                                : Icons.closed_caption_off_rounded,
                            color:
                                _showSubtitles ? Colors.white : Colors.white38,
                            size: 15.s(context),
                          ),
                          SizedBox(width: 8.s(context)),
                          Text(
                            widget.sourceName ?? 'Auto',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11.s(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _fmt(duration),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.s(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context) {
    final expired = _streamLikelyExpired();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 64.s(context)),
          SizedBox(height: 16.s(context)),
          Text(
            expired
                ? 'Stream link expired. Re-extract from the web player.'
                : 'Playback failed — DRM or unsupported stream.',
            style: TextStyle(color: Colors.white, fontSize: 20.s(context)),
            textAlign: TextAlign.center,
          ),
          if (_errorMessage != null) ...[
            SizedBox(height: 8.s(context)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.s(context)),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12.s(context),
                ),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          SizedBox(height: 24.s(context)),
          // Without a tmdbId there is nothing to re-extract from, so the
          // button is dropped and Back takes the autofocus — the error view
          // must never render with nothing focused on a D-pad.
          if (widget.tmdbId != null) ...[
            _ErrorButton(
              label: 'Try another source',
              autofocus: true,
              onPressed: _reExtract,
            ),
            SizedBox(height: 12.s(context)),
          ],
          _ErrorButton(
            label: 'Back',
            autofocus: widget.tmdbId == null,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _ErrorButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  const _ErrorButton({
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: 24.s(context),
                vertical: 12.s(context),
              ),
              decoration: BoxDecoration(
                color: hasFocus ? Colors.white : Colors.white24,
                borderRadius: BorderRadius.circular(4.s(context)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: hasFocus ? Colors.black : Colors.white,
                  fontSize: 16.s(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compact Subtitles / Source dropdown anchored above the control bar.
///
/// Deliberately not a dialog: playback keeps running behind it and only the
/// corner of the screen is covered, so a subtitle change can be judged
/// against the picture it applies to.
class _OptionsPanel extends StatelessWidget {
  const _OptionsPanel({
    required this.tracks,
    required this.activeSubKey,
    required this.embeddedUrl,
    required this.pinnedSourceName,
    required this.playingSourceName,
    required this.onOff,
    required this.onTrack,
    required this.onEmbedded,
    required this.onSource,
  });

  final List<SubtitleTrack> tracks;
  final String? activeSubKey;
  final String? embeddedUrl;

  /// What the user pinned (null = Auto) — this is what gets the tick.
  final String? pinnedSourceName;

  /// What is actually playing right now, shown as a subdued "playing" dot so
  /// Auto still tells you which provider it landed on.
  final String? playingSourceName;
  final VoidCallback onOff;
  final ValueChanged<SubtitleTrack> onTrack;
  final VoidCallback onEmbedded;

  /// null = Auto (race every provider).
  final ValueChanged<StreamServer?> onSource;

  /// Keeps UP/DOWN inside the panel: at the first or last row the traversal
  /// simply fails and the key is swallowed, instead of leaking out to the
  /// video surface behind.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      if (TvInput.shouldDropVerticalRepeat(e)) return KeyEventResult.handled;
      FocusManager.instance.primaryFocus?.focusInDirection(
        k == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Providers happily return several tracks with the same language and no
  /// release name, which would render as a column of identical rows. Number
  /// the repeats so each row names something the user can tell apart.
  List<String> _uniqueLabels() {
    final counts = <String, int>{};
    for (final t in tracks) {
      counts[t.label] = (counts[t.label] ?? 0) + 1;
    }
    final seen = <String, int>{};
    return [
      for (final t in tracks)
        if ((counts[t.label] ?? 0) > 1)
          '${t.label} ${seen[t.label] = (seen[t.label] ?? 0) + 1}'
        else
          t.label,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final labels = _uniqueLabels();
    // The English tracks land several seconds into playback and are inserted
    // above 'Embedded'. Reconciled positionally the highlight would stay on
    // the slot and the labels would slide under it, so the two fixed rows are
    // keyed and the insert is matched around them. The track rows themselves
    // stay unkeyed: their keys are scraped slugs with no dedup upstream, and a
    // repeated slug in a keyed list is a hard framework error.
    final subs = <Widget>[
      _OptionRow(
        key: const ValueKey('off'),
        label: 'Off',
        active: activeSubKey == null,
        autofocus: activeSubKey == null,
        onPressed: onOff,
      ),
      for (var i = 0; i < tracks.length; i++)
        _OptionRow(
          label: labels[i],
          active: activeSubKey == tracks[i].key,
          autofocus: activeSubKey == tracks[i].key,
          onPressed: () => onTrack(tracks[i]),
        ),
      if (embeddedUrl != null && embeddedUrl!.isNotEmpty)
        _OptionRow(
          key: const ValueKey('embedded'),
          label: 'Embedded',
          active: activeSubKey == embeddedUrl,
          autofocus: activeSubKey == embeddedUrl,
          onPressed: onEmbedded,
        ),
    ];

    final sources = <Widget>[
      _OptionRow(
        label: 'Auto',
        active: pinnedSourceName == null,
        autofocus: false,
        onPressed: () => onSource(null),
      ),
      for (final s in streamServers)
        _OptionRow(
          label: s.name,
          active: s.name == pinnedSourceName,
          playing: s.name == playingSourceName,
          onPressed: () => onSource(s),
        ),
    ];

    return Positioned(
      right: 32.s(context),
      bottom: 88.s(context),
      child: TvFadeIn(
        child: FocusScope(
          autofocus: true,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: TvRowFocusGroup(
              child: Container(
                padding: EdgeInsets.all(14.s(context)),
                decoration: BoxDecoration(
                  color: const Color(0xF21A1A22),
                  borderRadius: BorderRadius.circular(12.s(context)),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OptionsColumn(
                          icon: Icons.closed_caption_rounded,
                          title: 'Subtitles',
                          children: subs,
                        ),
                        SizedBox(width: 10.s(context)),
                        _OptionsColumn(
                          icon: Icons.dns_rounded,
                          title: 'Source',
                          children: sources,
                        ),
                      ],
                    ),
                    SizedBox(height: 10.s(context)),
                    Text(
                      'BACK to close',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10.s(context),
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One titled column of the dropdown.
class _OptionsColumn extends StatelessWidget {
  const _OptionsColumn({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 158.s(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              8.s(context),
              0,
              8.s(context),
              8.s(context),
            ),
            child: Row(
              children: [
                Icon(icon, color: kNetflixRed, size: 13.s(context)),
                SizedBox(width: 6.s(context)),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: kTextGrey,
                    fontSize: 10.s(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // Rows are a fixed extent and the column is capped at a whole
          // number of them, so a long list scrolls instead of ending on a
          // sliced row.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _OptionRow.extent.s(context) * 6,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemExtent: _OptionRow.extent.s(context),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single selectable row. Focus reads as a white pill with black text, the
/// same language the nav tabs and hero buttons use; the current value keeps a
/// red tick so it stays identifiable while focus is elsewhere.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.label,
    required this.active,
    required this.onPressed,
    this.autofocus = false,
    this.playing = false,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;
  final bool autofocus;

  /// Currently streaming, which in Auto is not the same as being chosen.
  final bool playing;

  /// Logical height of one row, including the gap below it.
  static const double extent = 29;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      revealAlignment: 0.5,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: TvMotion.focus,
          curve: TvMotion.curve,
          margin: EdgeInsets.only(bottom: 3.s(context)),
          padding: EdgeInsets.symmetric(horizontal: 8.s(context)),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: focused ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6.s(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        focused
                            ? Colors.black
                            : (active ? kTextWhite : kTextGrey),
                    fontSize: 12.5.s(context),
                    fontWeight:
                        active || focused ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (playing && !active) ...[
                SizedBox(width: 4.s(context)),
                Container(
                  width: 5.s(context),
                  height: 5.s(context),
                  decoration: BoxDecoration(
                    color: focused ? Colors.black54 : kNetflixRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              if (active) ...[
                SizedBox(width: 4.s(context)),
                Icon(
                  Icons.check_rounded,
                  size: 13.s(context),
                  color: focused ? Colors.black : kNetflixRed,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
