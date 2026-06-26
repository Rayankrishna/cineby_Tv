import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/browse_results_page.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final SearchStore _searchStore = SearchStore();

  @override
  void initState() {
    super.initState();
    _searchStore.fetchTrendingResults();
    historyStore.fetchContinueWatching();
    // Pull full history, then seed the "For You" rail from it.
    historyStore.fetch().then((_) => _loadForYou());
  }

  Future<void> _loadForYou() async {
    final seeds = historyStore.items
        .map((h) => (tmdbId: h.tmdbId, mediaType: h.mediaType))
        .toList();
    await _searchStore.fetchForYou(seeds);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kDeepBlack,
      child: Observer(
        builder: (_) {
          final stillLoading = _searchStore.isLoading &&
              _searchStore.trendingResults.isEmpty &&
              _searchStore.topMovies.isEmpty;
          if (stillLoading) {
            return const Center(child: CircularProgressIndicator(color: kNetflixRed));
          }
          if (_searchStore.errorMessage != null && _searchStore.trendingResults.isEmpty) {
            return Center(
              child: Text(
                _searchStore.errorMessage!,
                style: TextStyle(color: kTextWhite, fontSize: 14.s(context)),
              ),
            );
          }
          final trending = _searchStore.trendingResults;
          final hero = trending.isNotEmpty ? trending.first : null;

          return CustomScrollView(
            slivers: [
              if (hero != null) SliverToBoxAdapter(child: _Hero(item: hero)),
              if (historyStore.continueWatching.isNotEmpty)
                _SliverHistoryRow(
                  title: 'Continue Watching',
                  items: historyStore.continueWatching,
                ),
              if (_searchStore.forYou.isNotEmpty)
                _SliverRow(
                  title: 'For You',
                  items: _searchStore.forYou,
                  defaultMediaType: 'movie',
                ),
              const _SliverCategoriesRow(),
              if (trending.isNotEmpty)
                _SliverRow(title: 'Trending Now', items: trending, defaultMediaType: 'movie'),
              if (_searchStore.topMovies.isNotEmpty)
                _SliverRow(
                  title: 'Popular Movies',
                  items: _searchStore.topMovies,
                  defaultMediaType: 'movie',
                ),
              if (_searchStore.topSeries.isNotEmpty)
                _SliverRow(
                  title: 'Popular TV Shows',
                  items: _searchStore.topSeries,
                  defaultMediaType: 'tv',
                ),
              if (_searchStore.topAnime.isNotEmpty)
                _SliverRow(
                  title: 'Anime',
                  items: _searchStore.topAnime,
                  defaultMediaType: 'tv',
                ),
              if (_searchStore.actionMovies.isNotEmpty)
                _SliverRow(
                  title: 'Best in Action',
                  items: _searchStore.actionMovies,
                  defaultMediaType: 'movie',
                ),
              if (_searchStore.comedyMovies.isNotEmpty)
                _SliverRow(
                  title: 'Best in Comedy',
                  items: _searchStore.comedyMovies,
                  defaultMediaType: 'movie',
                ),
              if (_searchStore.dramaMovies.isNotEmpty)
                _SliverRow(
                  title: 'Best in Drama',
                  items: _searchStore.dramaMovies,
                  defaultMediaType: 'movie',
                ),
              if (_searchStore.horrorMovies.isNotEmpty)
                _SliverRow(
                  title: 'Best in Horror',
                  items: _searchStore.horrorMovies,
                  defaultMediaType: 'movie',
                ),
              if (_searchStore.sciFiMovies.isNotEmpty)
                _SliverRow(
                  title: 'Best in Sci-Fi',
                  items: _searchStore.sciFiMovies,
                  defaultMediaType: 'movie',
                ),
              SliverPadding(padding: EdgeInsets.only(bottom: 60.s(context))),
            ],
          );
        },
      ),
    );
  }
}

// ============== HERO ==============
class _Hero extends StatelessWidget {
  final SearchResult item;
  const _Hero({required this.item});

  String get _mediaType => item.mediaType ?? 'movie';

  void _openDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsPage(
          movieId: item.id.toString(),
          mediaType: _mediaType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SizedBox(
      height: size.height * 0.62,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop
          if (item.backdropPath != null || item.posterPath != null)
            Image.network(
              '$imgOriginal${item.backdropPath ?? item.posterPath}',
              fit: BoxFit.cover,
            )
          else
            Container(color: kSurfaceGrey),
          // Bottom fade-to-black
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    kDeepBlack.withOpacity(0.4),
                    kDeepBlack,
                  ],
                  stops: const [0.5, 0.85, 1.0],
                ),
              ),
            ),
          ),
          // Left fade for readable text
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    kDeepBlack.withOpacity(0.7),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          ),
          Positioned(
            left: 40.s(context),
            right: 40.s(context),
            bottom: 40.s(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.s(context),
                        vertical: 1.s(context),
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: kNetflixRed, width: 2.s(context)),
                      ),
                      child: Text(
                        'R',
                        style: TextStyle(
                          color: kNetflixRed,
                          fontSize: 11.s(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.s(context)),
                    Text(
                      _mediaType == 'tv' ? 'SERIES' : 'FILM',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.s(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.s(context),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.s(context)),
                Text(
                  item.title ?? item.name ?? 'Featured',
                  style: TextStyle(
                    color: kTextWhite,
                    fontSize: 64.s(context),
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: -1.0.s(context),
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.7),
                        blurRadius: 16.s(context),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.s(context)),
                SizedBox(
                  width: size.width * 0.45,
                  child: Text(
                    item.overview ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kTextWhite,
                      fontSize: 15.s(context),
                      height: 1.4,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 8.s(context),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 22.s(context)),
                Row(
                  children: [
                    _HeroPlayButton(
                      autofocus: true,
                      onPressed: () => _openDetails(context),
                    ),
                    SizedBox(width: 12.s(context)),
                    _HeroInfoButton(
                      onPressed: () => _openDetails(context),
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
}

void _scrollToTop(BuildContext context) {
  final position = Scrollable.maybeOf(context)?.position;
  if (position == null) return;
  if (position.pixels <= 0.5) return; // already there
  position.animateTo(
    0.0,
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeOut,
  );
}

class _HeroPlayButton extends StatelessWidget {
  final bool autofocus;
  final VoidCallback onPressed;
  const _HeroPlayButton({required this.autofocus, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onFocusChange: (f) {
        if (!f) return;
        _scrollToTop(context);
      },
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
          child: AnimatedScale(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: focused ? 1.06 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: 26.s(context),
                vertical: 12.s(context),
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4.s(context)),
                border: Border.all(
                  color: focused ? kNetflixRed : Colors.transparent,
                  width: 3.s(context),
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: kNetflixRed.withOpacity(0.55),
                          blurRadius: 28.s(context),
                          spreadRadius: 1.s(context),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, color: Colors.black, size: 26.s(context)),
                  SizedBox(width: 6.s(context)),
                  Text(
                    'Play',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 17.s(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _HeroInfoButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _HeroInfoButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        if (!f) return;
        _scrollToTop(context);
      },
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
          child: AnimatedScale(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: focused ? 1.06 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: 26.s(context),
                vertical: 12.s(context),
              ),
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white.withOpacity(0.28)
                    : Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4.s(context)),
                border: Border.all(
                  color: focused ? kTextWhite : Colors.transparent,
                  width: 3.s(context),
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.25),
                          blurRadius: 24.s(context),
                          spreadRadius: 1.s(context),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 22.s(context)),
                  SizedBox(width: 8.s(context)),
                  Text(
                    'More Info',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17.s(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ============== ROWS ==============
class _SliverRow extends StatelessWidget {
  final String title;
  final List<SearchResult> items;
  final String defaultMediaType;
  const _SliverRow({
    required this.title,
    required this.items,
    required this.defaultMediaType,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: 28.s(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 40.s(context),
                bottom: 10.s(context),
              ),
              child: Text(
                title,
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 18.s(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2.s(context),
                ),
              ),
            ),
            SizedBox(
              // Headroom for the focused card's 1.15x scale (198 -> ~228).
              height: 234.s(context),
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 40.s(context)),
                scrollDirection: Axis.horizontal,
                // Don't clip — let the focused card scale up (and cast its
                // shadow) in both dimensions instead of having the height cut.
                clipBehavior: Clip.none,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  // Column centers the card vertically and passes a loose
                  // height constraint, so the card keeps its 198px height
                  // and scales into the row's headroom rather than filling it.
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PosterCard(
                        posterPath: item.posterPath,
                        fallbackLabel: item.title ?? item.name,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovieDetailsPage(
                                movieId: item.id.toString(),
                                mediaType: item.mediaType ?? defaultMediaType,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverHistoryRow extends StatelessWidget {
  final String title;
  final List<HistoryItem> items;
  const _SliverHistoryRow({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: 28.s(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 40.s(context),
                bottom: 10.s(context),
              ),
              child: Text(
                title,
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 18.s(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2.s(context),
                ),
              ),
            ),
            SizedBox(
              // Headroom for the focused card's 1.15x scale (198 -> ~228).
              height: 234.s(context),
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 40.s(context)),
                scrollDirection: Axis.horizontal,
                // Don't clip — let the focused card scale up (and cast its
                // shadow) in both dimensions instead of having the height cut.
                clipBehavior: Clip.none,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final h = items[i];
                  // Column centers the card vertically and passes a loose
                  // height constraint, so the card keeps its 198px height
                  // and scales into the row's headroom rather than filling it.
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PosterCard(
                        posterPath: h.posterPath ?? h.backdropPath,
                        fallbackLabel: h.title,
                        progress: h.progressFraction,
                        badge: h.mediaType == 'tv' && h.seasonNumber != null && h.episodeNumber != null
                            ? 'S${h.seasonNumber}·E${h.episodeNumber}'
                            : null,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovieDetailsPage(
                                movieId: h.tmdbId.toString(),
                                mediaType: h.mediaType,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final String? posterPath;
  final String? fallbackLabel;
  final double? progress;
  final String? badge;
  final VoidCallback onPressed;

  const _PosterCard({
    required this.posterPath,
    required this.fallbackLabel,
    this.progress,
    this.badge,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.s(context)),
      child: Builder(builder: (outerCtx) {
        return Focus(
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
          onFocusChange: (focused) {
            if (!focused) return;
            // Pull the focused row to the top of the viewport. The card itself
            // is short — using its parent row's full height isn't necessary
            // because keepVisibleAtStart only nudges when not already visible.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!outerCtx.mounted) return;
              Scrollable.ensureVisible(
                outerCtx,
                alignment: 0.0,
                alignmentPolicy:
                    ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
              );
            });
          },
          child: Builder(builder: (ctx) {
            final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 132.s(context),
              // Explicit poster (2:3) height so the card keeps its own size
              // instead of being stretched to the row's full height — that's
              // what let the scale grow width but not height.
              height: 198.s(context),
              // Reserve room below the poster. The 1.15x focus scale grows the
              // card past its layout box; on the last row (Anime) the scroll
              // view reveals it flush to the screen bottom, so without this the
              // scaled bottom border would be clipped off-screen.
              margin: EdgeInsets.only(bottom: 20.s(context)),
              transform: focused
                  ? (Matrix4.identity()..scale(1.15))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4.s(context)),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.7),
                          blurRadius: 22.s(context),
                          offset: Offset(0, 10.s(context)),
                        ),
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.s(context)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterPath != null)
                      Image.network('$imgW300$posterPath', fit: BoxFit.cover)
                    else
                      Container(
                        color: kSurfaceGrey,
                        alignment: Alignment.center,
                        padding: EdgeInsets.all(6.s(context)),
                        child: Text(
                          fallbackLabel ?? '?',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kTextWhite, fontSize: 12.s(context)),
                        ),
                      ),
                    if (focused)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: kTextWhite, width: 2.s(context)),
                            borderRadius: BorderRadius.circular(4.s(context)),
                          ),
                        ),
                      ),
                    if (badge != null)
                      Positioned(
                        top: 6.s(context),
                        left: 6.s(context),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.s(context),
                            vertical: 2.s(context),
                          ),
                          decoration: BoxDecoration(
                            color: kDeepBlack.withOpacity(0.78),
                            borderRadius: BorderRadius.circular(2.s(context)),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              color: kTextWhite,
                              fontSize: 9.s(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    if (progress != null && progress! > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.black54,
                          valueColor: const AlwaysStoppedAnimation(kNetflixRed),
                          minHeight: 3.s(context).clamp(2.0, 5.0),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        );
      }),
    );
  }
}

// ============== CATEGORIES (BROWSE BY GENRE) ==============
// A horizontal rail of focusable genre chips — the TV-friendly equivalent of
// the phone's "Categories" picker. Selecting one opens the paginated
// GenreResultsPage for that genre.
class _SliverCategoriesRow extends StatelessWidget {
  const _SliverCategoriesRow();

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

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: 28.s(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 40.s(context),
                bottom: 10.s(context),
              ),
              child: Text(
                'Categories',
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 18.s(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2.s(context),
                ),
              ),
            ),
            SizedBox(
              height: 64.s(context),
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 40.s(context)),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                // +1 for the leading Anime chip (TV discover, not a plain
                // movie genre).
                itemCount: _genres.length + 1,
                itemBuilder: (ctx, i) {
                  final pad = EdgeInsets.symmetric(
                    horizontal: 6.s(context),
                    vertical: 8.s(context),
                  );
                  if (i == 0) {
                    return Padding(
                      padding: pad,
                      child: _CategoryChip(
                        label: 'Anime',
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => const GenreResultsPage(
                              genreId: 16,
                              genreName: 'Anime',
                              mediaType: 'tv',
                              extraQuery: '&with_origin_country=JP|CN',
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  final g = _genres[i - 1];
                  return Padding(
                    padding: pad,
                    child: _CategoryChip(
                      label: g.$2,
                      onTap: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => GenreResultsPage(
                            genreId: g.$1,
                            genreName: g.$2,
                            mediaType: 'movie',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.onTap});

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 22.s(context)),
          decoration: BoxDecoration(
            color: _focused ? kNetflixRed : Colors.white12,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: _focused ? kNetflixRed : Colors.white24,
              width: 2,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: kTextWhite,
              fontSize: 14.s(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
