import 'dart:async';

import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/browse_results_page.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_image.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

// ---- Home layout (design px at 960x540) ----
//
// The screen is split into a billboard (top) and rows (bottom). The rows live
// in their own clipped viewport that starts at [_rowsTop]; the focused row is
// always pinned to the top of it, so the highlight never moves vertically.
// While the hero buttons are focused the whole rows viewport is slid down by
// [_featuredShift] to give the billboard room.
const double _rowsTop = 232;
const double _featuredShift = 140;
const double _infoTop = 70;
const double _infoWidth = 430;
const double _actionsTop = 304;

/// How long focus must rest on a card before the billboard switches to it.
/// Keeps the backdrop from thrashing while the user scrubs along a row.
const Duration _spotlightDelay = Duration(milliseconds: 240);

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, this.tab});
  final String title;
  final TvTabHandle? tab;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

/// What the billboard shows for one title.
class _Spotlight {
  const _Spotlight({
    required this.key,
    required this.title,
    this.backdropPath,
    this.overview,
    this.rating,
    this.meta = const [],
  });

  final String key;
  final String title;
  final String? backdropPath;
  final String? overview;
  final double? rating;
  final List<String> meta;
}

class _HomeCard {
  const _HomeCard({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    required this.posterPath,
    required this.spotlight,
    required this.preview,
    this.progress,
    this.badge,
  });

  final int tmdbId;
  final String mediaType;
  final String title;
  final String? posterPath;
  final _Spotlight spotlight;
  final DetailPreview preview;
  final double? progress;
  final String? badge;
}

class _HomeRow {
  const _HomeRow(this.key, this.title, this.cards) : genres = false;
  const _HomeRow.genres()
    : key = 'genres',
      title = 'Browse by Genre',
      cards = const [],
      genres = true;

  final String key;
  final String title;
  final List<_HomeCard> cards;
  final bool genres;
}

String? _yearOf(String? date) =>
    (date != null && date.length >= 4) ? date.substring(0, 4) : null;

_HomeCard _cardFromResult(SearchResult r, String fallbackType) {
  final type = r.mediaType ?? fallbackType;
  final title = r.title ?? r.name ?? 'Untitled';
  final year = _yearOf(r.releaseDate ?? r.firstAirDate);
  final rating = (r.voteAverage ?? 0) > 0 ? r.voteAverage : null;
  return _HomeCard(
    tmdbId: r.id,
    mediaType: type,
    title: title,
    posterPath: r.posterPath,
    spotlight: _Spotlight(
      key: '$type:${r.id}',
      title: title,
      backdropPath: r.backdropPath,
      overview: r.overview,
      rating: rating,
      meta: [if (year != null) year, type == 'tv' ? 'Series' : 'Film'],
    ),
    preview: DetailPreview(
      title: title,
      backdropPath: r.backdropPath,
      overview: r.overview,
      year: year,
      rating: rating,
    ),
  );
}

_HomeCard _cardFromHistory(HistoryItem h) {
  final title = h.title ?? 'Untitled';
  final isEpisode =
      h.mediaType == 'tv' && h.seasonNumber != null && h.episodeNumber != null;
  final duration = h.durationSeconds ?? 0;
  final minutesLeft =
      duration > 0 ? ((duration - h.progressSeconds) / 60).ceil() : 0;
  return _HomeCard(
    tmdbId: h.tmdbId,
    mediaType: h.mediaType,
    title: title,
    posterPath: h.posterPath ?? h.backdropPath,
    progress: h.progressFraction,
    badge: isEpisode ? 'S${h.seasonNumber} · E${h.episodeNumber}' : null,
    spotlight: _Spotlight(
      key: 'resume:${h.mediaType}:${h.tmdbId}',
      title: title,
      backdropPath: h.backdropPath,
      overview: 'Pick up where you left off.',
      meta: [
        if (isEpisode) 'Season ${h.seasonNumber}, Episode ${h.episodeNumber}',
        if (minutesLeft > 0) '$minutesLeft min left',
      ],
    ),
    preview: DetailPreview(title: title, backdropPath: h.backdropPath),
  );
}

class _MyHomePageState extends State<MyHomePage> {
  final SearchStore _store = SearchStore();
  final ScrollController _rowsController = ScrollController();
  final FocusNode _playNode = FocusNode(debugLabel: 'hero-play');

  /// Title currently shown on the billboard.
  final ValueNotifier<_Spotlight?> _spotlight = ValueNotifier(null);

  /// Index of the row holding focus, or -1 while the hero is focused.
  final ValueNotifier<int> _activeRow = ValueNotifier(-1);

  Timer? _spotlightTimer;
  String? _activeRowKey;

  /// Set while the hero holds focus, consumed by the first card focused
  /// after it (see [_onCardFocused]).
  bool _leavingHero = true;
  List<String> _rowKeys = const [];

  @override
  void initState() {
    super.initState();
    widget.tab?.onBack = _handleBack;
    _load();
    historyStore.fetchContinueWatching();
    // Pull full history, then seed the "For You" rail from it.
    historyStore.fetch().then((_) => _loadForYou());
  }

  @override
  void dispose() {
    if (widget.tab?.onBack == _handleBack) widget.tab?.onBack = null;
    _spotlightTimer?.cancel();
    _rowsController.dispose();
    _playNode.dispose();
    _spotlight.dispose();
    _activeRow.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _store.fetchTrendingResults();
    if (!mounted) return;
    if (_activeRow.value < 0) _spotlight.value = _featured?.spotlight;
  }

  Future<void> _loadForYou() async {
    final seeds =
        historyStore.items
            .map((h) => (tmdbId: h.tmdbId, mediaType: h.mediaType))
            .toList();
    await _store.fetchForYou(seeds);
  }

  /// The title promoted on the billboard: today's top trending entry that has
  /// artwork to show.
  _HomeCard? get _featured {
    for (final r in _store.trendingResults) {
      if (r.backdropPath != null) return _cardFromResult(r, 'movie');
    }
    return null;
  }

  List<_HomeRow> _buildRows() {
    List<_HomeCard> cards(List<SearchResult> items, String type) => [
      for (final r in items) _cardFromResult(r, type),
    ];

    final continueWatching = historyStore.continueWatching;
    return [
      if (continueWatching.isNotEmpty)
        _HomeRow('continue', 'Continue Watching', [
          for (final h in continueWatching) _cardFromHistory(h),
        ]),
      if (_store.forYou.isNotEmpty)
        _HomeRow('for-you', 'For You', cards(_store.forYou, 'movie')),
      if (_store.trendingResults.isNotEmpty)
        _HomeRow(
          'trending',
          'Trending Now',
          cards(_store.trendingResults, 'movie'),
        ),
      const _HomeRow.genres(),
      if (_store.topMovies.isNotEmpty)
        _HomeRow('movies', 'Popular Movies', cards(_store.topMovies, 'movie')),
      if (_store.topSeries.isNotEmpty)
        _HomeRow('series', 'Popular TV Shows', cards(_store.topSeries, 'tv')),
      if (_store.topAnime.isNotEmpty)
        _HomeRow('anime', 'Anime', cards(_store.topAnime, 'tv')),
      if (_store.actionMovies.isNotEmpty)
        _HomeRow(
          'action',
          'Best in Action',
          cards(_store.actionMovies, 'movie'),
        ),
      if (_store.comedyMovies.isNotEmpty)
        _HomeRow(
          'comedy',
          'Best in Comedy',
          cards(_store.comedyMovies, 'movie'),
        ),
      if (_store.dramaMovies.isNotEmpty)
        _HomeRow('drama', 'Best in Drama', cards(_store.dramaMovies, 'movie')),
      if (_store.horrorMovies.isNotEmpty)
        _HomeRow(
          'horror',
          'Best in Horror',
          cards(_store.horrorMovies, 'movie'),
        ),
      if (_store.sciFiMovies.isNotEmpty)
        _HomeRow('scifi', 'Best in Sci-Fi', cards(_store.sciFiMovies, 'movie')),
    ];
  }

  // ---- Focus choreography ----

  void _showSpotlight(_Spotlight? spot, {bool immediate = false}) {
    _spotlightTimer?.cancel();
    if (immediate) {
      _spotlight.value = spot;
      return;
    }
    _spotlightTimer = Timer(_spotlightDelay, () {
      if (mounted) _spotlight.value = spot;
    });
  }

  void _onCardFocused(_HomeCard card) {
    // Stepping down from the hero already cross-fades the billboard layout,
    // so bring the new title in with it rather than as a second fade a beat
    // later. Between cards, wait for focus to settle.
    _showSpotlight(card.spotlight, immediate: _leavingHero);
    _leavingHero = false;
  }

  void _onHeroFocused() {
    _leavingHero = true;
    _activeRowKey = null;
    _activeRow.value = -1;
    _showSpotlight(_featured?.spotlight, immediate: true);
    if (_rowsController.hasClients && _rowsController.offset > 0.5) {
      _rowsController.animateTo(
        0,
        duration: TvMotion.scroll,
        curve: TvMotion.curve,
      );
    }
  }

  void _onRowFocused(String key) {
    _activeRowKey = key;
    final index = _rowKeys.indexOf(key);
    if (index >= 0) _activeRow.value = index;
  }

  /// BACK from anywhere in the rows returns to the hero before the shell
  /// hands focus to the nav bar.
  bool _handleBack() {
    if (_activeRow.value < 0 || !_playNode.canRequestFocus) return false;
    _playNode.requestFocus();
    return true;
  }

  /// Rows can appear after first paint (Continue Watching, For You). When
  /// that shifts the focused row, re-pin it instead of leaving it displaced.
  void _syncRowKeys(List<String> keys) {
    if (_listEquals(keys, _rowKeys)) return;
    _rowKeys = keys;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _activeRowKey;
      if (key == null) return;
      final index = keys.indexOf(key);
      if (index < 0) return;
      _activeRow.value = index;
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext != null && focusContext.mounted) {
        TvSection.maybeOf(focusContext)?.reveal();
      }
    });
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _openCard(_HomeCard card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => MovieDetailsPage(
              movieId: card.tmdbId.toString(),
              mediaType: card.mediaType,
              preview: card.preview,
            ),
      ),
    );
  }

  void _openGenre(
    int id,
    String name, {
    String type = 'movie',
    String extra = '',
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => GenreResultsPage(
              genreId: id,
              genreName: name,
              mediaType: type,
              extraQuery: extra,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kDeepBlack,
      child: Observer(
        builder: (_) {
          final featured = _featured;
          final rows = _buildRows();
          final hasCatalogue = rows.any((r) => !r.genres);

          if (!hasCatalogue) {
            if (_store.isLoading) return const _HomeSkeleton();
            return TvMessage(
              icon: Icons.cloud_off_rounded,
              title: "Can't reach the catalogue",
              detail: 'Check your connection and try again.',
              actions: [
                TvButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  autofocus: true,
                  onPressed: _load,
                ),
              ],
            );
          }

          _syncRowKeys([for (final r in rows) r.key]);
          return _buildHome(context, featured, rows);
        },
      ),
    );
  }

  Widget _buildHome(
    BuildContext context,
    _HomeCard? featured,
    List<_HomeRow> rows,
  ) {
    final gutter = kTvGutter.s(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<_Spotlight?>(
          valueListenable: _spotlight,
          builder:
              (_, spot, __) => TvBillboardBackdrop(path: spot?.backdropPath),
        ),

        // Title, metadata and synopsis.
        Positioned(
          left: gutter,
          top: _infoTop.s(context),
          width: _infoWidth.s(context),
          height: (_actionsTop - _infoTop - 12).s(context),
          child: ValueListenableBuilder<int>(
            valueListenable: _activeRow,
            builder:
                (_, active, __) => ValueListenableBuilder<_Spotlight?>(
                  valueListenable: _spotlight,
                  builder:
                      (_, spot, __) =>
                          _BillboardInfo(spot: spot, featured: active < 0),
                ),
          ),
        ),

        // Hero actions. They stay in the tree while rows are focused (just
        // invisible) so UP from the first row has somewhere to land.
        if (featured != null)
          Positioned(
            left: gutter,
            top: _actionsTop.s(context),
            child: ValueListenableBuilder<int>(
              valueListenable: _activeRow,
              builder:
                  (_, active, __) => AnimatedOpacity(
                    opacity: active < 0 ? 1 : 0,
                    duration: TvMotion.fade,
                    child: _HeroActions(
                      featured: featured,
                      playNode: _playNode,
                      browsing: active >= 0,
                      onFocused: _onHeroFocused,
                      onPlay: () => _openCard(featured),
                    ),
                  ),
            ),
          ),

        // Rows.
        Positioned(
          left: 0,
          right: 0,
          top: _rowsTop.s(context),
          bottom: 0,
          child: ValueListenableBuilder<int>(
            valueListenable: _activeRow,
            builder:
                (_, active, child) => TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    end: active < 0 ? _featuredShift.s(context) : 0,
                  ),
                  duration: const Duration(milliseconds: 340),
                  curve: TvMotion.curve,
                  builder:
                      (_, dy, child) => Transform.translate(
                        offset: Offset(0, dy),
                        child: child,
                      ),
                  child: child,
                ),
            child: ListView(
              controller: _rowsController,
              padding: EdgeInsets.only(bottom: 260.s(context)),
              // Keep a row either side built so UP/DOWN always has a target.
              scrollCacheExtent: ScrollCacheExtent.pixels(480.s(context)),
              children: [
                for (var i = 0; i < rows.length; i++)
                  _HomeRowView(
                    key: ValueKey(rows[i].key),
                    row: rows[i],
                    index: i,
                    activeRow: _activeRow,
                    onRowFocused: () => _onRowFocused(rows[i].key),
                    onCardFocused: _onCardFocused,
                    onCardPressed: _openCard,
                    onGenrePressed: _openGenre,
                    onExitTop:
                        featured == null
                            ? null
                            : () => _playNode.requestFocus(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============== BILLBOARD ==============

class _BillboardInfo extends StatelessWidget {
  const _BillboardInfo({required this.spot, required this.featured});

  final _Spotlight? spot;

  /// True while the hero buttons are focused: larger type, anchored just
  /// above the buttons. Otherwise a compact block under the nav bar.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final spot = this.spot;
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
          spot == null
              ? const SizedBox.expand(key: ValueKey('empty'))
              : Align(
                key: ValueKey('${spot.key}|$featured'),
                alignment: featured ? Alignment.bottomLeft : Alignment.topLeft,
                child: _BillboardText(spot: spot, featured: featured),
              ),
    );
  }
}

class _BillboardText extends StatelessWidget {
  const _BillboardText({required this.spot, required this.featured});
  final _Spotlight spot;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final shadow = [
      Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 12),
    ];
    final overview = spot.overview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          spot.title,
          maxLines: featured ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: kTextWhite,
            fontSize: (featured ? 40 : 28).s(context),
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: -0.5.s(context),
            shadows: shadow,
          ),
        ),
        SizedBox(height: (featured ? 10 : 6).s(context)),
        TvMetaLine(rating: spot.rating, items: spot.meta),
        if (overview != null && overview.isNotEmpty) ...[
          SizedBox(height: (featured ? 10 : 7).s(context)),
          Text(
            overview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: (featured ? 13.5 : 12.5).s(context),
              height: 1.4,
              shadows: shadow,
            ),
          ),
        ],
      ],
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.featured,
    required this.playNode,
    required this.browsing,
    required this.onFocused,
    required this.onPlay,
  });

  final _HomeCard featured;
  final FocusNode playNode;

  /// While a row is focused the buttons are hidden, so arrow keys must not
  /// wander onto them; they are only reachable via UP from the first row.
  final bool browsing;
  final VoidCallback onFocused;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final listKey = '${featured.tmdbId}:${featured.mediaType}';
    return TvRowFocusGroup(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TvButton(
            label: 'Play',
            icon: Icons.play_arrow_rounded,
            autofocus: true,
            focusNode: playNode,
            skipTraversal: browsing,
            reveal: false,
            onFocusChange: (f) {
              if (f) onFocused();
            },
            onPressed: onPlay,
          ),
          SizedBox(width: 10.s(context)),
          Observer(
            builder: (_) {
              final inList = watchlistStore.containsCache[listKey] ?? false;
              return TvButton(
                label: 'My List',
                icon: inList ? Icons.check_rounded : Icons.add_rounded,
                skipTraversal: browsing,
                reveal: false,
                onFocusChange: (f) {
                  if (f) onFocused();
                },
                onPressed:
                    () => watchlistStore.toggle(
                      tmdbId: featured.tmdbId,
                      mediaType: featured.mediaType,
                      title: featured.title,
                      posterPath: featured.posterPath,
                    ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============== ROWS ==============

class _HomeRowView extends StatelessWidget {
  const _HomeRowView({
    super.key,
    required this.row,
    required this.index,
    required this.activeRow,
    required this.onRowFocused,
    required this.onCardFocused,
    required this.onCardPressed,
    required this.onGenrePressed,
    required this.onExitTop,
  });

  final _HomeRow row;
  final int index;
  final ValueListenable<int> activeRow;
  final VoidCallback onRowFocused;
  final ValueChanged<_HomeCard> onCardFocused;
  final ValueChanged<_HomeCard> onCardPressed;
  final void Function(int id, String name, {String type, String extra})
  onGenrePressed;

  /// Where UP leads from the first row (the hero), if anywhere.
  final VoidCallback? onExitTop;

  static const List<(int, String)> _genres = [
    (28, 'Action'),
    (12, 'Adventure'),
    (16, 'Animation'),
    (35, 'Comedy'),
    (80, 'Crime'),
    (99, 'Documentary'),
    (18, 'Drama'),
    (10751, 'Family'),
    (14, 'Fantasy'),
    (36, 'History'),
    (27, 'Horror'),
    (10402, 'Music'),
    (9648, 'Mystery'),
    (10749, 'Romance'),
    (878, 'Science Fiction'),
    (53, 'Thriller'),
    (10752, 'War'),
    (37, 'Western'),
  ];

  Widget _buildBody(BuildContext context) {
    if (row.genres) {
      return TvFlowRail(
        height: 50.s(context),
        children: [
          // Anime is a TV discover query, not a plain movie genre.
          TvChip(
            label: 'Anime',
            onPressed:
                () => onGenrePressed(
                  16,
                  'Anime',
                  type: 'tv',
                  extra: '&with_origin_country=JP|CN',
                ),
          ),
          for (final g in _genres)
            TvChip(label: g.$2, onPressed: () => onGenrePressed(g.$1, g.$2)),
        ],
      );
    }
    return TvPosterRail(
      storageId: 'home-${row.key}',
      count: row.cards.length,
      cardBuilder: (context, i) {
        final card = row.cards[i];
        return TvPosterCard(
          posterPath: card.posterPath,
          title: card.title,
          progress: card.progress,
          badge: card.badge,
          onFocused: () => onCardFocused(card),
          onPressed: () => onCardPressed(card),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final exitTop = index == 0 ? onExitTop : null;
    return ValueListenableBuilder<int>(
      valueListenable: activeRow,
      // Rows that have scrolled above the focused one fade away rather than
      // being sliced by the top edge of the rows viewport.
      builder:
          (_, active, child) => AnimatedOpacity(
            opacity: index < active ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          ),
      child: TvSection(
        alignment: 0,
        onFocusChange: (focused) {
          if (focused) onRowFocused();
        },
        onKeyEvent:
            exitTop == null
                ? null
                : (node, event) {
                  if (event.logicalKey != LogicalKeyboardKey.arrowUp) {
                    return KeyEventResult.ignored;
                  }
                  if (event is! KeyUpEvent) exitTop();
                  return KeyEventResult.handled;
                },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [TvSectionTitle(title: row.title), _buildBody(context)],
        ),
      ),
    );
  }
}

// ============== LOADING ==============

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return TvPulse(
      child: Stack(
        children: [
          Positioned(
            left: kTvGutter.s(context),
            top: 150.s(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TvSkeletonBox(width: 300.s(context), height: 34.s(context)),
                SizedBox(height: 14.s(context)),
                TvSkeletonBox(width: 150.s(context), height: 12.s(context)),
                SizedBox(height: 14.s(context)),
                TvSkeletonBox(width: 400.s(context), height: 11.s(context)),
                SizedBox(height: 8.s(context)),
                TvSkeletonBox(width: 360.s(context), height: 11.s(context)),
                SizedBox(height: 22.s(context)),
                Row(
                  children: [
                    TvSkeletonBox(width: 96.s(context), height: 36.s(context)),
                    SizedBox(width: 10.s(context)),
                    TvSkeletonBox(width: 110.s(context), height: 36.s(context)),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: (_rowsTop + _featuredShift).s(context),
            child: const TvPosterRailSkeleton(),
          ),
        ],
      ),
    );
  }
}
