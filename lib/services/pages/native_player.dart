import 'dart:async';

import 'package:cineby_tv/services/config.dart';
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
  bool _hasError = false;
  String? _errorMessage;
  Timer? _hideTimer;
  Timer? _progressTimer;
  DateTime? _streamExtractedAt;

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
        await _loadSubtitles(widget.subtitleUrl!);
      }

      _controller.addListener(_handleVideoError);

      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());

      if (mounted) {
        setState(() {
          _initialized = true;
        });
        _focusNode.requestFocus();
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

  Future<void> _loadSubtitles(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: widget.httpHeaders);
      if (response.statusCode == 200) {
        final caption = WebVTTCaptionFile(response.body);
        await _controller.setClosedCaptionFile(Future.value(caption));
      }
    } catch (_) {
      // Subtitle load failed — keep playing without them.
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
    setState(() => _showSubtitles = !_showSubtitles);
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
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
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
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
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
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
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
              _buildControls(context),
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
