import 'package:cached_network_image/cached_network_image.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:flutter/material.dart';

/// Which TMDB image family a path belongs to; each has its own size ladder.
enum TmdbImageKind { poster, backdrop, profile, still }

const String _tmdbImageBase = 'https://image.tmdb.org/t/p/';

const Map<TmdbImageKind, List<int>> _tmdbWidths = {
  TmdbImageKind.poster: [154, 185, 342, 500, 780],
  // Capped at 1280: a 4K "original" backdrop is several MB and tens of MB
  // decoded, for an image that sits behind gradients anyway.
  TmdbImageKind.backdrop: [300, 780, 1280],
  TmdbImageKind.profile: [185],
  TmdbImageKind.still: [185, 300, 500],
};

/// URL for [path] at the smallest TMDB size that still looks sharp when shown
/// [physicalWidth] device pixels wide. Downloading a size that matches the
/// slot is the single biggest win for scroll smoothness on TV hardware.
String tmdbImageUrl(String path, TmdbImageKind kind, double physicalWidth) {
  final widths = _tmdbWidths[kind]!;
  var chosen = widths.last;
  for (final w in widths) {
    // Allow ~15% upscaling before stepping up a size.
    if (w >= physicalWidth * 0.85) {
      chosen = w;
      break;
    }
  }
  return '${_tmdbImageBase}w$chosen$path';
}

/// Disk-cached artwork that fades in over a neutral placeholder instead of
/// popping, and is decoded at the size it is actually drawn.
class TvImage extends StatelessWidget {
  const TvImage({
    super.key,
    required this.path,
    required this.kind,
    required this.width,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallback,
  });

  /// TMDB path such as `/abc.jpg`; null shows [fallback].
  final String? path;
  final TmdbImageKind kind;

  /// Logical width the image is laid out at — used to pick the download and
  /// decode size, not to size the widget.
  final double width;
  final BoxFit fit;
  final Alignment alignment;

  /// Shown when there is no artwork or it fails to load.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final empty = fallback ?? const ColoredBox(color: kSurfaceGrey);
    final path = this.path;
    if (path == null || path.isEmpty) return empty;
    final physical = width * MediaQuery.devicePixelRatioOf(context);
    return CachedNetworkImage(
      imageUrl: tmdbImageUrl(path, kind, physical),
      fit: fit,
      alignment: alignment,
      memCacheWidth: physical.round().clamp(64, 1920).toInt(),
      fadeInDuration: TvMotion.fade,
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => const ColoredBox(color: kSurfaceGrey),
      errorWidget: (_, __, ___) => empty,
    );
  }
}

/// Full-bleed backdrop that cross-fades whenever [path] changes.
///
/// The next image is fetched and decoded *before* the swap, so the previous
/// one stays on screen until its replacement is ready — no flash to black.
class TvBackdrop extends StatefulWidget {
  const TvBackdrop({
    super.key,
    required this.path,
    required this.width,
    this.alignment = Alignment.topCenter,
  });

  final String? path;
  final double width;
  final Alignment alignment;

  @override
  State<TvBackdrop> createState() => _TvBackdropState();
}

class _TvBackdropState extends State<TvBackdrop> {
  ImageProvider? _shown;
  String? _shownPath;
  String? _wantedPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(TvBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  void _load() {
    final path = widget.path;
    if (path == _wantedPath) return;
    _wantedPath = path;
    if (path == null || path.isEmpty) {
      if (_shown != null) {
        setState(() {
          _shown = null;
          _shownPath = null;
        });
      }
      return;
    }
    final physical = widget.width * MediaQuery.devicePixelRatioOf(context);
    final provider = ResizeImage.resizeIfNeeded(
      physical.round().clamp(64, 1920).toInt(),
      null,
      CachedNetworkImageProvider(
        tmdbImageUrl(path, TmdbImageKind.backdrop, physical),
      ),
    );
    // precacheImage completes its future on failure too, so record the error
    // and keep the previous backdrop rather than fading it out to black.
    var failed = false;
    precacheImage(
      provider,
      context,
      onError: (_, __) => failed = true,
    ).then((_) {
      // Skip if the fetch failed, or focus has moved on to another title.
      if (failed || !mounted || _wantedPath != path) return;
      setState(() {
        _shown = provider;
        _shownPath = path;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return AnimatedSwitcher(
      duration: TvMotion.fade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder:
          (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
      child:
          shown == null
              ? const SizedBox.expand(key: ValueKey('none'))
              : SizedBox.expand(
                key: ValueKey(_shownPath),
                child: Image(
                  image: shown,
                  fit: BoxFit.cover,
                  alignment: widget.alignment,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
    );
  }
}

/// The cinematic backdrop used behind the home billboard and detail pages:
/// artwork pinned to the top-right, dissolving into the page background on
/// its left and bottom edges so text and rows stay readable over it.
///
/// Place it directly in a `Stack` that fills the screen.
class TvBillboardBackdrop extends StatelessWidget {
  const TvBillboardBackdrop({super.key, required this.path});

  final String? path;

  /// Share of the screen width the artwork covers.
  static const double widthFactor = 0.78;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * widthFactor;
    return Align(
      alignment: Alignment.topRight,
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        // Isolated so scrolling rows above it never re-rasterises the image.
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              TvBackdrop(path: path, width: width),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [kDeepBlack, Color(0x000B0B10)],
                    stops: [0.0, 0.42],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000B0B10), Color(0xB30B0B10), kDeepBlack],
                    stops: [0.3, 0.7, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
