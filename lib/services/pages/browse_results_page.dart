import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/services/tmdb_client.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';

/// Browse all titles of one TMDB genre. Opened from genre chips on the home
/// and details pages.
class GenreResultsPage extends StatefulWidget {
  final int genreId;
  final String genreName;
  final String mediaType; // 'movie' | 'tv'
  // Extra discover filters, e.g. Anime: '&with_origin_country=JP|CN'.
  final String extraQuery;

  const GenreResultsPage({
    super.key,
    required this.genreId,
    required this.genreName,
    this.mediaType = 'movie',
    this.extraQuery = '',
  });

  @override
  State<GenreResultsPage> createState() => _GenreResultsPageState();
}

class _GenreResultsPageState extends State<GenreResultsPage> {
  final ScrollController _scroll = ScrollController();
  final List<SearchResult> _items = [];
  final Set<int> _seenIds = {};

  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  bool _initialLoad = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Prefetch well before the edge so D-pad focus traversal never hits an
    // empty bottom while the next page loads.
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 900.s(context)) {
      _loadNextPage();
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _initialLoad = true;
    });
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loading || _page >= _totalPages) return;
    _loading = true;
    final next = _page + 1;
    try {
      final res = await tmdbDio.get(
        genreDiscoverUrl(
          widget.genreId,
          widget.mediaType,
          next,
          widget.extraQuery,
        ),
      );
      final parsed = SearchResponse.fromJson(res.data);
      _totalPages = parsed.totalPages;
      final now = DateTime.now();
      final fresh = <SearchResult>[];
      for (final r in parsed.results) {
        if (r.posterPath == null) continue;
        if (_seenIds.contains(r.id)) continue;
        final d = r.releaseDate ?? r.firstAirDate;
        if (d == null || d.isEmpty) continue;
        final parsedDate = DateTime.tryParse(d);
        if (parsedDate == null || parsedDate.isAfter(now)) continue;
        _seenIds.add(r.id);
        r.mediaType ??= widget.mediaType;
        fresh.add(r);
      }
      if (!mounted) return;
      setState(() {
        _page = next;
        _items.addAll(fresh);
        _initialLoad = false;
        _error = null; // a later page landing repairs a stale footer
      });
      if (fresh.isEmpty && _page < _totalPages) {
        _loading = false;
        await _loadNextPage();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initialLoad = false;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_initialLoad) {
      body = const TvPosterGridSkeleton(rows: 3);
    } else if (_items.isEmpty) {
      body =
          _error != null
              ? _LoadError(onRetry: _retry)
              : TvMessage(
                icon: Icons.movie_filter_outlined,
                title: 'Nothing released yet',
                actions: [
                  TvButton(
                    label: 'Go Back',
                    icon: Icons.arrow_back_rounded,
                    autofocus: true,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              );
    } else {
      final failed = _error != null;
      final hasMore = _page < _totalPages && !failed;
      body = CustomScrollView(
        controller: _scroll,
        slivers: [
          _PosterGridSliver(items: _items, defaultMediaType: widget.mediaType),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 14.s(context), 0, 70.s(context)),
              child: Center(
                child:
                    hasMore
                        ? SizedBox(
                          width: 22.s(context),
                          height: 22.s(context),
                          child: const CircularProgressIndicator(
                            color: kNetflixRed,
                            strokeWidth: 2.5,
                          ),
                        )
                        : Text(
                          failed
                              ? "Couldn't load more — scroll to try again"
                              : "That's everything",
                          style: TextStyle(
                            color: kTextGrey,
                            fontSize: 12.s(context),
                          ),
                        ),
              ),
            ),
          ),
        ],
      );
    }
    return _BrowseScaffold(
      title: widget.genreName,
      subtitle: widget.mediaType == 'tv' ? 'Series' : 'Movies',
      body: body,
    );
  }
}

/// Every movie + TV show an actor has appeared in. Opened from cast tiles
/// on the details page.
class PersonFilmographyPage extends StatefulWidget {
  final int personId;
  final String personName;

  const PersonFilmographyPage({
    super.key,
    required this.personId,
    required this.personName,
  });

  @override
  State<PersonFilmographyPage> createState() => _PersonFilmographyPageState();
}

class _PersonFilmographyPageState extends State<PersonFilmographyPage> {
  late Future<List<SearchResult>> _future = _load();

  Future<List<SearchResult>> _load() async {
    final responses = await Future.wait([
      tmdbDio.get(personMovieCreditsUrl(widget.personId)),
      tmdbDio.get(personTvCreditsUrl(widget.personId)),
    ]);
    final now = DateTime.now();

    SearchResult? toResult(Map<String, dynamic> json, String mediaType) {
      final releaseDate = json['release_date'] as String?;
      final firstAirDate = json['first_air_date'] as String?;
      final d = releaseDate ?? firstAirDate;
      if (d == null || d.isEmpty) return null;
      final parsed = DateTime.tryParse(d);
      if (parsed == null || parsed.isAfter(now)) return null;
      if (json['poster_path'] == null) return null;
      return SearchResult(
        id: json['id'] as int,
        title: json['title'] as String?,
        name: json['name'] as String?,
        originalTitle: json['original_title'] as String?,
        originalName: json['original_name'] as String?,
        overview: json['overview'] as String?,
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        mediaType: mediaType,
        releaseDate: releaseDate,
        firstAirDate: firstAirDate,
        voteAverage: (json['vote_average'] as num?)?.toDouble(),
        voteCount: json['vote_count'] as int?,
      );
    }

    final movies =
        (responses[0].data['cast'] as List<dynamic>? ?? [])
            .map((e) => toResult(e as Map<String, dynamic>, 'movie'))
            .whereType<SearchResult>();
    final tv =
        (responses[1].data['cast'] as List<dynamic>? ?? [])
            .map((e) => toResult(e as Map<String, dynamic>, 'tv'))
            .whereType<SearchResult>();

    // An actor can be credited several times on one title (multiple roles);
    // keep each title once.
    final seen = <String>{};
    final merged = [
      for (final r in [...movies, ...tv])
        if (seen.add('${r.mediaType}:${r.id}')) r,
    ]..sort((a, b) => (b.voteCount ?? 0).compareTo(a.voteCount ?? 0));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return _BrowseScaffold(
      title: widget.personName,
      subtitle: 'Filmography',
      body: FutureBuilder<List<SearchResult>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const TvPosterGridSkeleton(rows: 3);
          }
          if (snap.hasError) {
            return _LoadError(onRetry: () => setState(() => _future = _load()));
          }
          final items = snap.data ?? const <SearchResult>[];
          if (items.isEmpty) {
            return TvMessage(
              icon: Icons.movie_filter_outlined,
              title: 'Nothing released yet',
              actions: [
                TvButton(
                  label: 'Go Back',
                  icon: Icons.arrow_back_rounded,
                  autofocus: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              _PosterGridSliver(items: items, defaultMediaType: 'movie'),
              SliverToBoxAdapter(child: SizedBox(height: 70.s(context))),
            ],
          );
        },
      ),
    );
  }
}

class _BrowseScaffold extends StatelessWidget {
  const _BrowseScaffold({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvPageTitle(title: title, subtitle: subtitle),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return TvMessage(
      icon: Icons.cloud_off_rounded,
      title: "Couldn't load this page",
      detail: 'Check your connection and try again.',
      actions: [
        TvButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          autofocus: true,
          onPressed: onRetry,
        ),
        TvButton(
          label: 'Go Back',
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// 6-column poster wall; the first card takes focus when the page opens.
class _PosterGridSliver extends StatelessWidget {
  const _PosterGridSliver({
    required this.items,
    required this.defaultMediaType,
  });

  final List<SearchResult> items;
  final String defaultMediaType;

  void _open(BuildContext context, SearchResult r) {
    final date = r.releaseDate ?? r.firstAirDate;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => MovieDetailsPage(
              movieId: r.id.toString(),
              mediaType: r.mediaType ?? defaultMediaType,
              preview: DetailPreview(
                title: r.title ?? r.name,
                backdropPath: r.backdropPath,
                overview: r.overview,
                year:
                    (date != null && date.length >= 4)
                        ? date.substring(0, 4)
                        : null,
                rating: r.voteAverage,
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        kTvGutter.s(context),
        12.s(context),
        kTvGutter.s(context),
        0,
      ),
      sliver: SliverGrid(
        gridDelegate: tvPosterGridDelegate(context),
        delegate: SliverChildBuilderDelegate((context, i) {
          final r = items[i];
          return TvPosterCard(
            width: double.infinity,
            autofocus: i == 0,
            posterPath: r.posterPath,
            title: r.title ?? r.name,
            onPressed: () => _open(context, r),
          );
        }, childCount: items.length),
      ),
    );
  }
}
