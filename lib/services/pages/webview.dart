import 'package:cineby_tv/services/pages/native_player.dart';
import 'package:cineby_tv/services/stream_extractor.dart';
import 'package:cineby_tv/services/stream_servers.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Playback entry point. Instead of loading one provider's embed in a
/// visible webview and making the user switch when it fails, this races
/// EVERY provider at once (headless) and hands off to the native player with
/// whichever returns a stream first — the losing extractors are torn down.
class MyWidget extends StatefulWidget {
  final String?
  url; // ignored when tmdbId is present (kept for call-site compat)
  final String? title;
  final int? tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final int initialProgressSeconds;
  final int? durationSeconds;
  final String? posterPath;
  final String? backdropPath;
  // IMDb id (from the TMDB detail response) — used for YIFY subtitles.
  final String? imdbId;

  /// Extract from this provider only, instead of racing them all. Set when
  /// the user picks a source in the player; `null` means Auto (race).
  /// Falls back to a full race if the chosen provider yields nothing.
  final StreamServer? forcedServer;

  const MyWidget({
    super.key,
    this.url,
    this.forcedServer,
    this.title,
    this.tmdbId,
    this.mediaType = 'movie',
    this.seasonNumber,
    this.episodeNumber,
    this.initialProgressSeconds = 0,
    this.durationSeconds,
    this.posterPath,
    this.backdropPath,
    this.imdbId,
  });

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  bool _racing = false;
  bool _failed = false;
  bool _handedOff = false;

  /// The pinned provider actually in use — from [MyWidget.forcedServer] or,
  /// on a normal Play, from the choice saved in a previous session. Drives
  /// the prep card's copy so a pin never looks like it was ignored.
  String? _pinnedSource;

  /// Live extractors for the race in flight, so backing out of this page
  /// tears down their headless webviews instead of letting five of them run
  /// on for the rest of the timeout.
  final List<StreamExtractionHandle> _handles = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    if (widget.tmdbId != null) {
      _startRace();
    } else {
      _failed = true;
    }
  }

  @override
  void dispose() {
    // On handoff the native player re-enables the wakelock in its own
    // initState (and pushReplacement disposes this page afterwards), so only
    // release it when the user actually backs out of extraction.
    if (!_handedOff) {
      WakelockPlus.disable();
    }
    // Only a handoff leaves a winner worth keeping; every other exit (BACK,
    // Try again) should stop the extractors now.
    if (!_handedOff) {
      for (final h in _handles) {
        h.cancel();
      }
    }
    _handles.clear();
    super.dispose();
  }

  Future<void> _startRace() async {
    for (final h in _handles) {
      h.cancel();
    }
    _handles.clear();
    setState(() {
      _racing = true;
      _failed = false;
    });
    // An explicit pick (this playback, or one saved from a previous session)
    // wins over the race; Auto races every provider as before.
    final chosen = widget.forcedServer ?? await loadSelectedServer();
    if (!mounted || _handedOff) return;
    if (chosen != null) setState(() => _pinnedSource = chosen.name);
    var raced = await raceServersForStream(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
      servers: chosen == null ? null : [chosen],
      // Give up on a single pinned provider well before the full-race budget:
      // a stale pin otherwise doubles time-to-play before the fallback starts.
      timeout:
          chosen == null
              ? const Duration(seconds: 45)
              : const Duration(seconds: 15),
      outHandles: _handles,
    );
    if (!mounted || _handedOff) return;
    // The chosen provider had nothing for this title — rather than dead-end,
    // fall back to the full race so playback still starts.
    if (raced == null && chosen != null) {
      // Pinned provider came up empty — say so while the full race runs.
      setState(() => _pinnedSource = null);
      raced = await raceServersForStream(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType,
        seasonNumber: widget.seasonNumber,
        episodeNumber: widget.episodeNumber,
        outHandles: _handles,
      );
      if (!mounted || _handedOff) return;
    }
    if (raced == null) {
      setState(() {
        _racing = false;
        _failed = true;
      });
      return;
    }
    _handoff(raced);
  }

  void _handoff(RacedStream raced) {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => NativePlayerPage(
              videoUrl: raced.stream.videoUrl,
              httpHeaders: raced.stream.headers,
              subtitleUrl: raced.stream.subtitleUrl,
              sourceName: raced.server.name,
              imdbId: widget.imdbId,
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
          fit: StackFit.expand,
          children: [
            // Backdrop or solid black behind the prep card.
            if ((widget.backdropPath ?? widget.posterPath) != null)
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.black54,
                  BlendMode.darken,
                ),
                child: Image.network(
                  '$imgW500${widget.backdropPath ?? widget.posterPath}',
                  fit: BoxFit.cover,
                  // Decoded at screen width, not the multi-MB original: this
                  // card is on screen for a second while extraction runs.
                  cacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  errorBuilder: (_, __, ___) => Container(color: kDeepBlack),
                ),
              )
            else
              Container(color: kDeepBlack),
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
              child:
                  _failed
                      ? _FailureCard(
                        title: widget.title,
                        onRetry: _startRace,
                        onCancel: () => Navigator.of(context).maybePop(),
                      )
                      : _LoadingCard(
                        title: widget.title,
                        racing: _racing,
                        sourceName: _pinnedSource,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String? title;
  final bool racing;

  /// The pinned provider, when the user chose one; null means Auto.
  final String? sourceName;
  const _LoadingCard({
    required this.title,
    required this.racing,
    this.sourceName,
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
              Shadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10.s(context),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.s(context)),
        Text(
          // Naming the provider matters once the user has pinned one: the
          // generic copy made a deliberate switch look like it was ignored.
          sourceName == null
              ? 'Finding the best source'
              : 'Loading $sourceName',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14.s(context)),
        ),
      ],
    );
  }
}

class _FailureCard extends StatelessWidget {
  final String? title;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _FailureCard({
    required this.title,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(32.s(context)),
      constraints: BoxConstraints(maxWidth: 560.s(context)),
      decoration: BoxDecoration(
        color: kSurfaceGrey.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12.s(context)),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: kNetflixRed, size: 48.s(context)),
          SizedBox(height: 16.s(context)),
          Text(
            'No source returned a stream',
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
                ? 'Every provider failed or timed out for "$title".'
                : 'Every provider failed or timed out.',
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
                label: 'Try again',
                icon: Icons.refresh_rounded,
                isPrimary: true,
                autofocus: true,
                onPressed: onRetry,
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
      child: Builder(
        builder: (ctx) {
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
                color:
                    isPrimary
                        ? (focused
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.92))
                        : (focused
                            ? Colors.white24
                            : Colors.white.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(4.s(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isPrimary ? Colors.black : Colors.white,
                    size: 20.s(context),
                  ),
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
        },
      ),
    );
  }
}
