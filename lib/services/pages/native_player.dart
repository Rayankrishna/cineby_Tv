import 'dart:async';

import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/webview.dart';
import 'package:cineby_tv/services/stream_servers.dart';
import 'package:cineby_tv/services/subtitle_service.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class NativePlayerPage extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> httpHeaders;
  final String? subtitleUrl;
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

  // Seek indicator
  String? _seekHint;
  Timer? _seekHintTimer;

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
    _scheduleHideControls();
  }

  Future<void> _initController() async {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      httpHeaders: widget.httpHeaders,
    );

    try {
      await _controller.initialize();
      if (widget.initialProgressSeconds > 0) {
        await _controller.seekTo(Duration(seconds: widget.initialProgressSeconds));
      }
      await _controller.play();

      if (widget.subtitleUrl != null && widget.subtitleUrl!.isNotEmpty) {
        await _loadSubtitles(widget.subtitleUrl!, userInitiated: false);
      }

      _controller.addListener(_handleVideoError);

      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());

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
      }
    }
  }

  void _handleVideoError() {
    if (!mounted) return;
    if (_controller.value.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = _controller.value.errorDescription;
      });
    }
  }

  /// Load a captured iframe subtitle URL (.srt or .vtt → normalised to VTT).
  Future<void> _loadSubtitles(String url, {bool userInitiated = true}) async {
    if (userInitiated) _userPickedSub = true;
    try {
      final response =
          await http.get(Uri.parse(url), headers: widget.httpHeaders);
      if (response.statusCode == 200) {
        final body = response.body;
        // A captured "subtitle" URL is often an HTML page or non-subtitle
        // resource — never feed that to the caption parser.
        if (looksLikeHtml(body) ||
            (!body.contains('-->') &&
                !body.trimLeft().startsWith('WEBVTT'))) {
          return;
        }
        final vtt = body.trimLeft().startsWith('WEBVTT')
            ? body
            : SubtitleService.instance.srtToVtt(body);
        await _controller.setClosedCaptionFile(Future.value(WebVTTCaptionFile(vtt)));
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
      await _controller
          .setClosedCaptionFile(Future.value(WebVTTCaptionFile(vtt)));
    }
  }

  /// Turn subtitles off (clear the caption track).
  Future<void> _clearSubtitles({bool userInitiated = true}) async {
    if (userInitiated) _userPickedSub = true;
    setState(() {
      _activeSubKey = null;
      _showSubtitles = false;
    });
    await _controller
        .setClosedCaptionFile(Future.value(WebVTTCaptionFile('WEBVTT\n\n')));
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
    debugPrint('[SUBS] player: ${tracks.length} english tracks '
        '(imdb=$imdb tmdb=$id s=${widget.seasonNumber} e=${widget.episodeNumber})');
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

  void _scheduleHideControls() {
    _hideTimer?.cancel();
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

  Future<void> _seekBy(int seconds) async {
    if (!_controller.value.isInitialized) return;
    final cur = _controller.value.position;
    final total = _controller.value.duration;
    var target = cur + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    await _controller.seekTo(target);
    _flashSeekHint(seconds > 0 ? '+${seconds}s' : '${seconds}s');
    _revealControls();
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // Open the Options sheet (subtitles toggle + source switcher) so
      // remotes without a 'C' key or media-stop button can still reach
      // the subtitle control.
      _revealControls();
      _showOptionsDialog();
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

  // ============== OPTIONS SHEET ==============

  void _showOptionsDialog() {
    if (widget.tmdbId == null) return;
    // Pause while the dialog is open so audio doesn't keep playing under it.
    final wasPlaying = _controller.value.isPlaying;
    if (wasPlaying) _controller.pause();

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Dialog(
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
                  _OptionsHeader(
                      icon: Icons.closed_caption, label: 'Subtitles'),
                  // Off + every available track (yify English first, then any
                  // captured iframe sub). ENTER selects.
                  _OptionsRow(
                    label: 'Off',
                    icon: Icons.closed_caption_off,
                    autofocus: _activeSubKey == null,
                    trailing: _activeSubKey == null ? 'On' : null,
                    onTap: () {
                      _clearSubtitles();
                      setSheetState(() {});
                    },
                  ),
                  for (final t in _subTracks)
                    _OptionsRow(
                      label: t.label,
                      icon: Icons.closed_caption,
                      autofocus: _activeSubKey == t.key,
                      trailing: _activeSubKey == t.key ? 'On' : null,
                      onTap: () {
                        _setTrack(t);
                        setSheetState(() {});
                      },
                    ),
                  if (widget.subtitleUrl != null &&
                      widget.subtitleUrl!.isNotEmpty)
                    _OptionsRow(
                      label: 'Embedded',
                      icon: Icons.closed_caption,
                      autofocus: _activeSubKey == widget.subtitleUrl,
                      trailing:
                          _activeSubKey == widget.subtitleUrl ? 'On' : null,
                      onTap: () {
                        _loadSubtitles(widget.subtitleUrl!);
                        setSheetState(() {});
                      },
                    ),
                  SizedBox(height: 8.s(context)),
                  _OptionsHeader(icon: Icons.dns_rounded, label: 'Source'),
                  for (final s in streamServers)
                    _OptionsRow(
                      label: s.name,
                      icon: Icons.play_circle_outline_rounded,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _switchSource(s);
                      },
                    ),
                  SizedBox(height: 8.s(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (!mounted) return;
      if (wasPlaying) _controller.play();
      _focusNode.requestFocus();
    });
  }

  void _switchSource(StreamServer server) {
    if (widget.tmdbId == null) return;
    _switchingSource = true;
    _saveProgress();
    final newUrl = server.buildUrl(
      widget.tmdbId!,
      widget.mediaType,
      widget.seasonNumber,
      widget.episodeNumber,
    );
    // pushReplacement to MyWidget — fresh webview boots, re-extracts on the
    // new provider, and lands back in NativePlayerPage. Current progress
    // carries over via initialProgressSeconds so playback resumes near where
    // the user was.
    final resumeSeconds = _controller.value.position.inSeconds;
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
          initialProgressSeconds: resumeSeconds > 0
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
    return Scaffold(
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
              const Center(child: CircularProgressIndicator(color: kNetflixRed)),

            if (_initialized && !_hasError && _showSubtitles)
              _buildCaption(context),

            if (_initialized && !_hasError && _seekHint != null)
              _buildSeekHint(context),

            if (_initialized && !_hasError && _showControls)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller,
                builder: (_, __, ___) => _buildControls(context),
              ),
          ],
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
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.s(context), vertical: 6.s(context)),
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
        );
      },
    );
  }

  Widget _buildSeekHint(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 28.s(context), vertical: 16.s(context)),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12.s(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _seekHint!.startsWith('-') ? Icons.fast_rewind : Icons.fast_forward,
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
    final position = value.position;
    final duration = value.duration;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.8),
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
                Icon(Icons.arrow_back, color: Colors.white, size: 24.s(context)),
                SizedBox(width: 8.s(context)),
                Text(
                  'Back',
                  style: TextStyle(color: Colors.white70, fontSize: 14.s(context)),
                ),
                const Spacer(),
                if (widget.title != null)
                  Text(
                    widget.title!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20.s(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          // Center play/pause icon
          Center(
            child: Icon(
              value.isPlaying ? Icons.pause_circle : Icons.play_circle,
              color: Colors.white.withOpacity(0.9),
              size: 96.s(context),
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
                Container(
                  height: 4.s(context),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2.s(context)),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kNetflixRed,
                        borderRadius: BorderRadius.circular(2.s(context)),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8.s(context)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(position),
                      style: TextStyle(color: Colors.white, fontSize: 14.s(context)),
                    ),
                    Row(
                      children: [
                        Icon(
                          _showSubtitles ? Icons.closed_caption : Icons.closed_caption_off,
                          color: Colors.white70,
                          size: 18.s(context),
                        ),
                        SizedBox(width: 4.s(context)),
                        Text(
                          'C',
                          style: TextStyle(color: Colors.white54, fontSize: 12.s(context)),
                        ),
                      ],
                    ),
                    Text(
                      _fmt(duration),
                      style: TextStyle(color: Colors.white, fontSize: 14.s(context)),
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
                style: TextStyle(color: Colors.white54, fontSize: 12.s(context)),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          SizedBox(height: 24.s(context)),
          _ErrorButton(
            label: 'Watch in webview',
            autofocus: true,
            onPressed: () => Navigator.of(context).pop('fallback'),
          ),
          SizedBox(height: 12.s(context)),
          _ErrorButton(
            label: 'Back',
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
              padding: EdgeInsets.symmetric(horizontal: 24.s(context), vertical: 12.s(context)),
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

class _OptionsHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _OptionsHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24.s(context), 4.s(context), 24.s(context), 10.s(context)),
      child: Row(
        children: [
          Icon(icon, color: kNetflixRed, size: 20.s(context)),
          SizedBox(width: 10.s(context)),
          Text(
            label,
            style: TextStyle(
              color: kTextWhite,
              fontSize: 16.s(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionsRow extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? trailing;
  final bool autofocus;

  const _OptionsRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.trailing,
    this.autofocus = false,
  });

  @override
  State<_OptionsRow> createState() => _OptionsRowState();
}

class _OptionsRowState extends State<_OptionsRow> {
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
          vertical: 12.s(context),
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              color: _focused ? Colors.white : Colors.white70,
              size: 20.s(context),
            ),
            SizedBox(width: 14.s(context)),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 14.5.s(context),
                  fontWeight:
                      _focused ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (widget.trailing != null)
              Text(
                widget.trailing!,
                style: TextStyle(
                  color: kNetflixRed,
                  fontSize: 13.s(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
