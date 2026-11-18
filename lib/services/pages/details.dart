import 'dart:async';

import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/models/tv_detail_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/browse_results_page.dart';
import 'package:cineby_tv/services/pages/webview.dart';
import 'package:cineby_tv/services/tmdb_client.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/stores/tv_detail_store.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_image.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

/// What the card that opened this page already knows about the title. Shown
/// immediately so the page never opens on a blank spinner.
class DetailPreview {
  const DetailPreview({
    this.title,
    this.backdropPath,
    this.overview,
    this.year,
    this.rating,
  });

  final String? title;
  final String? backdropPath;
  final String? overview;
  final String? year;
  final double? rating;
}

class MovieDetailsPage extends StatefulWidget {
  final String movieId;
  final String mediaType; // 'movie' | 'tv'
  final DetailPreview? preview;

  /// Start playing as soon as the details needed to do so have loaded —
  /// what a button labelled "Play" is expected to do. The page is still the
  /// route underneath, so BACK out of the player lands here rather than
  /// throwing the user back to the rail they came from.
  final bool autoPlay;

  const MovieDetailsPage({
    super.key,
    required this.movieId,
    this.mediaType = 'movie',
    this.preview,
    this.autoPlay = false,
  });

  @override
  State<MovieDetailsPage> createState() => _MovieDetailsPageState();
}

typedef _CastEntry =
    ({int? id, String name, String? character, String? profilePath});

class _MovieDetailsPageState extends State<MovieDetailsPage> {
  final SearchStore _movieStore = SearchStore();
  final TvDetailStore _tvStore = TvDetailStore();
  final ScrollController _scroll = ScrollController();

  HistoryItem? _resume;
  bool _inWatchlist = false;
  bool _watchlistBusy = false;
  List<SearchResult> _similar = const [];

  // Season the user has moved onto but whose episodes aren't requested yet.
  int? _pendingSeason;
  Timer? _seasonTimer;

  /// One-shot, so returning from the player doesn't immediately re-enter it.
  bool _autoPlayed = false;

  /// A retry fired from the error card: keep that card (and the focused
  /// Retry button) mounted instead of swapping in the focusless skeleton.
  bool _retrying = false;

  int get _tmdbId => int.tryParse(widget.movieId) ?? 0;
  bool get _isTv => widget.mediaType == 'tv';

  @override
  void initState() {
    super.initState();
    final details = _loadDetails();
    final resume = _refreshResume();
    _loadSimilar();
    watchlistStore.checkContains(_tmdbId, widget.mediaType).then((in_) {
      if (mounted) setState(() => _inWatchlist = in_);
    });
    if (widget.autoPlay) {
      // Both, so an auto-start still picks up where the user left off.
      Future.wait([details, resume]).then((_) => _maybeAutoPlay());
    }
  }

  /// Fires once, after the detail fetch settles. If it failed there is
  /// nothing to play, so the page just stays put showing its error state.
  void _maybeAutoPlay() {
    if (!mounted || _autoPlayed) return;
    _autoPlayed = true;
    final r = _resume;
    final resumable = r != null && !r.completed;
    if (_isTv) {
      final tv = _tvStore.tvDetail;
      if (tv == null) return;
      if (resumable && r.seasonNumber != null && r.episodeNumber != null) {
        _playEpisode(
          tv,
          r.seasonNumber!,
          r.episodeNumber!,
          seekTo: r.progressSeconds,
        );
        return;
      }
      // Finished the last episode watched: start the one the hero's own
      // button offers, so Play from the billboard and Play on this page
      // never begin different episodes.
      final nextUp =
          (r != null && r.completed)
              ? _nextEpisodeAfter(tv, r.seasonNumber ?? 1, r.episodeNumber ?? 1)
              : null;
      if (nextUp != null) {
        _playEpisode(tv, nextUp.season, nextUp.episode);
      } else {
        _playFirstAvailableEpisode(tv);
      }
    } else {
      if (_movieStore.movieDetails == null) return;
      _playMovie(seekTo: resumable ? r.progressSeconds : 0);
    }
  }

  @override
  void dispose() {
    _seasonTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadDetails({bool keepErrorCard = false}) async {
    if (keepErrorCard && !_retrying) setState(() => _retrying = true);
    try {
      await (_isTv
          ? _tvStore.fetchTvDetail(_tmdbId)
          : _movieStore.fetchMovieDetails(widget.movieId));
    } finally {
      if (mounted && _retrying) setState(() => _retrying = false);
    }
  }

  Future<void> _refreshResume() async {
    final h =
        _isTv
            ? await historyStore.latestForShow(_tmdbId)
            : await historyStore.latestForMovie(_tmdbId);
    if (mounted) setState(() => _resume = h);
  }

  Future<void> _loadSimilar() async {
    try {
      final res = await tmdbDio.get(
        recommendationsUrl(_tmdbId, widget.mediaType),
      );
      final now = DateTime.now();
      final items =
          SearchResponse.fromJson(res.data).results.where((r) {
            if (r.posterPath == null) return false;
            final date = DateTime.tryParse(
              r.releaseDate ?? r.firstAirDate ?? '',
            );
            return date != null && !date.isAfter(now);
          }).toList();
      for (final r in items) {
        r.mediaType ??= widget.mediaType;
      }
      if (!mounted || items.isEmpty) return;
      final wasEmpty = _similar.isEmpty;
      setState(() => _similar = items);
      if (!wasEmpty) return;
      // This rail is inserted above Cast and Genres, so a late arrival
      // slides whatever holds focus down by its height while the scroll
      // offset stays put. Re-pin it, the way home does after a late row
      // appears (see _syncRowKeys).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Still true under a pushed player route, where primaryFocus points
        // into the other route and revealing would scroll the wrong page.
        if (ModalRoute.of(context)?.isCurrent != true) return;
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext != null && focusContext.mounted) {
          TvSection.maybeOf(focusContext)?.reveal();
        }
      });
    } catch (_) {
      // Recommendations are a nice-to-have; the page works without them.
    }
  }

  // ============== PLAYBACK ==============

  // No source picking — MyWidget races every provider and uses whichever
  // returns a stream first.
  void _playMovie({int seekTo = 0}) {
    final m = _movieStore.movieDetails;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => MyWidget(
              tmdbId: _tmdbId,
              mediaType: 'movie',
              imdbId: m?.imdbId,
              initialProgressSeconds: seekTo,
              title: m?.title,
              posterPath: m?.posterPath,
              backdropPath: m?.backdropPath,
            ),
      ),
    ).then((_) => _afterPlayback());
  }

  void _playFirstAvailableEpisode(TvDetail tv) {
    final season = tv.seasons.isNotEmpty ? tv.seasons.first.seasonNumber : 1;
    _playEpisode(tv, season, 1);
  }

  void _playEpisode(TvDetail tv, int season, int episode, {int seekTo = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => MyWidget(
              tmdbId: _tmdbId,
              mediaType: 'tv',
              imdbId: tv.imdbId,
              seasonNumber: season,
              episodeNumber: episode,
              initialProgressSeconds: seekTo,
              title: tv.name,
              posterPath: tv.posterPath,
              backdropPath: tv.backdropPath,
            ),
      ),
    ).then((_) => _afterPlayback());
  }

  /// Coming back from the player: pick up the new resume point here and in
  /// the home screen's Continue Watching row.
  void _afterPlayback() {
    if (!mounted) return;
    _refreshResume();
    historyStore.fetchContinueWatching();
  }

  Future<void> _toggleWatchlist() async {
    // A second press while the first is in flight reads the cache the add
    // already wrote and takes the remove branch, undoing it.
    if (_watchlistBusy) return;
    String? title, poster;
    if (_isTv) {
      title = _tvStore.tvDetail?.name;
      poster = _tvStore.tvDetail?.posterPath;
    } else {
      title = _movieStore.movieDetails?.title;
      poster = _movieStore.movieDetails?.posterPath;
    }
    // Flip the icon now: adding is two round trips, and this is the one
    // button on the page that doesn't navigate, so until it flips the press
    // reads as dead.
    final next = !_inWatchlist;
    setState(() {
      _watchlistBusy = true;
      _inWatchlist = next;
    });
    tvToast(context, next ? 'Added to My List' : 'Removed from My List');
    try {
      await watchlistStore.toggle(
        tmdbId: _tmdbId,
        mediaType: widget.mediaType,
        title: title,
        posterPath: poster,
      );
      final now = await watchlistStore.checkContains(_tmdbId, widget.mediaType);
      if (mounted) setState(() => _inWatchlist = now);
    } finally {
      if (mounted) setState(() => _watchlistBusy = false);
    }
  }

  void _selectSeason(TvDetail tv, int seasonNumber, {bool immediate = false}) {
    _seasonTimer?.cancel();
    if (_tvStore.selectedSeasonNumber == seasonNumber) {
      if (_pendingSeason != null) setState(() => _pendingSeason = null);
      return;
    }
    setState(() => _pendingSeason = seasonNumber);
    void go() {
      if (!mounted) return;
      _tvStore.fetchSeason(tv.id, seasonNumber);
      setState(() => _pendingSeason = null);
    }

    if (immediate) {
      go();
    } else {
      // Don't fire a request for every season the user arrows past.
      _seasonTimer = Timer(const Duration(milliseconds: 260), go);
    }
  }

  void _openTitle(SearchResult r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => MovieDetailsPage(
              movieId: r.id.toString(),
              mediaType: r.mediaType ?? widget.mediaType,
              preview: DetailPreview(
                title: r.title ?? r.name,
                backdropPath: r.backdropPath,
                overview: r.overview,
                rating: r.voteAverage,
              ),
            ),
      ),
    );
  }

  void _openGenre(int id, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => GenreResultsPage(
              genreId: id,
              genreName: name,
              mediaType: widget.mediaType,
            ),
      ),
    );
  }

  void _openPerson(_CastEntry actor) {
    final id = actor.id;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PersonFilmographyPage(personId: id, personName: actor.name),
      ),
    );
  }

  // ============== BUILD ==============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      body: Observer(builder: (_) => _isTv ? _buildTv() : _buildMovie()),
    );
  }

  Widget _buildMovie() {
    final movie = _movieStore.movieDetails;
    if (movie == null && (_retrying || !_movieStore.isLoading)) {
      return _buildError();
    }

    final preview = widget.preview;
    final cast = <_CastEntry>[
      for (final c in movie?.credits?.cast ?? const [])
        if ((c.name ?? '').isNotEmpty)
          (
            id: c.id,
            name: c.name!,
            character: c.character,
            profilePath: c.profilePath,
          ),
    ];
    String? director;
    for (final c in movie?.credits?.crew ?? const []) {
      if (c.job == 'Director') {
        director = c.name;
        break;
      }
    }
    final runtime = movie?.runtime;
    final year = _year(movie?.releaseDate) ?? preview?.year;
    final resume = _resume;
    final canResume = resume != null && !resume.completed;

    return _buildPage(
      backdropPath: movie?.backdropPath ?? preview?.backdropPath,
      hero: _DetailHero(
        kind: 'FILM',
        title: movie?.title ?? preview?.title ?? '',
        tagline: movie?.tagline,
        overview: movie?.overview ?? preview?.overview,
        rating: movie?.voteAverage ?? preview?.rating,
        meta: [
          if (year != null) year,
          if (runtime != null && runtime > 0) _formatRuntime(runtime),
        ],
        credits: [
          if (cast.isNotEmpty)
            ('Starring', cast.take(3).map((c) => c.name).join(', ')),
          if (director != null) ('Director', director),
        ],
        actions:
            movie == null
                ? null
                : [
                  if (canResume) ...[
                    TvButton(
                      key: const ValueKey('primary-play'),
                      label: 'Resume',
                      subLabel: _formatProgress(resume.progressSeconds),
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                      onPressed:
                          () => _playMovie(seekTo: resume.progressSeconds),
                    ),
                    TvButton(
                      key: const ValueKey('play-from-start'),
                      label: 'Play from Start',
                      icon: Icons.replay_rounded,
                      onPressed: _playMovie,
                    ),
                  ] else
                    TvButton(
                      key: const ValueKey('primary-play'),
                      label: 'Play',
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                      onPressed: _playMovie,
                    ),
                  _watchlistButton(),
                ],
      ),
      sections: [
        if (movie != null) ...[
          ..._commonSections(
            cast: cast,
            genres: [
              for (final g in movie.genres ?? const [])
                if (g.id != null && (g.name ?? '').isNotEmpty)
                  (id: g.id!, name: g.name!),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTv() {
    final tv = _tvStore.tvDetail;
    if (tv == null && (_retrying || !_tvStore.isLoading)) {
      return _buildError();
    }

    final preview = widget.preview;
    final cast = <_CastEntry>[
      for (final c in tv?.cast ?? const <CastMember>[])
        if (c.name.isNotEmpty)
          (
            id: c.id,
            name: c.name,
            character: c.character,
            profilePath: c.profilePath,
          ),
    ];
    final seasons = tv?.numberOfSeasons;
    final year = _year(tv?.firstAirDate) ?? preview?.year;
    final resume = _resume;
    final canResume = resume != null && !resume.completed;
    // Finished the episode they were on: offer the next one rather than
    // dropping them back at the premiere.
    final nextUp =
        tv != null && resume != null && resume.completed
            ? _nextEpisodeAfter(
              tv,
              resume.seasonNumber ?? 1,
              resume.episodeNumber ?? 1,
            )
            : null;

    return _buildPage(
      backdropPath: tv?.backdropPath ?? preview?.backdropPath,
      hero: _DetailHero(
        kind: 'SERIES',
        title: tv?.name ?? preview?.title ?? '',
        tagline: tv?.tagline,
        overview: tv?.overview ?? preview?.overview,
        rating: tv?.voteAverage ?? preview?.rating,
        meta: [
          if (year != null) year,
          if (seasons != null && seasons > 0)
            '$seasons Season${seasons == 1 ? '' : 's'}',
        ],
        credits: [
          if (cast.isNotEmpty)
            ('Starring', cast.take(3).map((c) => c.name).join(', ')),
          if (tv?.creatorName != null) ('Creator', tv!.creatorName!),
        ],
        actions:
            tv == null
                ? null
                : [
                  if (canResume) ...[
                    TvButton(
                      key: const ValueKey('primary-play'),
                      label: 'Resume',
                      subLabel:
                          'S${resume.seasonNumber ?? 1} · E${resume.episodeNumber ?? 1}'
                          ' · ${_formatProgress(resume.progressSeconds)}',
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                      onPressed:
                          () => _playEpisode(
                            tv,
                            resume.seasonNumber ?? 1,
                            resume.episodeNumber ?? 1,
                            seekTo: resume.progressSeconds,
                          ),
                    ),
                    TvButton(
                      key: const ValueKey('play-from-start'),
                      label: 'Play from Start',
                      icon: Icons.replay_rounded,
                      onPressed: () => _playFirstAvailableEpisode(tv),
                    ),
                  ] else if (nextUp != null)
                    TvButton(
                      key: const ValueKey('primary-play'),
                      label: 'Play',
                      subLabel: 'S${nextUp.season} · E${nextUp.episode}',
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                      onPressed:
                          () => _playEpisode(tv, nextUp.season, nextUp.episode),
                    )
                  else
                    TvButton(
                      key: const ValueKey('primary-play'),
                      label: 'Play',
                      subLabel: 'S1 · E1',
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                      onPressed: () => _playFirstAvailableEpisode(tv),
                    ),
                  _watchlistButton(),
                ],
      ),
      sections: [
        if (tv != null) ...[
          _EpisodesSection(
            key: const ValueKey('episodes'),
            store: _tvStore,
            tv: tv,
            resume: resume,
            pendingSeason: _pendingSeason,
            onSeasonFocused: (n) => _selectSeason(tv, n),
            onSeasonPressed: (n) => _selectSeason(tv, n, immediate: true),
            onPlay:
                (e) => _playEpisode(
                  tv,
                  e.seasonNumber,
                  e.episodeNumber,
                  seekTo: _resumePointFor(e),
                ),
          ),
          ..._commonSections(
            cast: cast,
            genres: [for (final g in tv.genres) (id: g.id, name: g.name)],
          ),
        ],
      ],
    );
  }

  /// The episode after [season]/[episode]. Prefers the season already
  /// loaded (it knows what has actually aired); otherwise falls back to
  /// TMDB's episode_count on the season summary.
  ({int season, int episode})? _nextEpisodeAfter(
    TvDetail tv,
    int season,
    int episode,
  ) {
    // Season metadata is authoritative. Deciding from the *currently loaded*
    // season instead would do two wrong things: a finale would find no
    // "episode + 1" and fall back to the premiere, and the answer would
    // change as focus moved across the season chips (which load seasons),
    // silently retargeting the hero's primary button.
    for (var i = 0; i < tv.seasons.length; i++) {
      final s = tv.seasons[i];
      if (s.seasonNumber != season) continue;
      final count = s.episodeCount ?? 0;
      final next =
          (count == 0 || episode < count)
              ? (season: season, episode: episode + 1)
              : (i + 1 < tv.seasons.length
                  ? (season: tv.seasons[i + 1].seasonNumber, episode: 1)
                  : null);
      if (next == null) return null;
      // Only suppress it when we positively know it has not aired yet.
      return _hasAired(next) == false ? null : next;
    }
    return null;
  }

  /// Whether [target] has aired. null when that season's episode list is not
  /// loaded, i.e. we cannot tell — callers treat that as "offer it".
  bool? _hasAired(({int season, int episode}) target) {
    final loaded = _tvStore.selectedSeason;
    if (loaded == null || loaded.seasonNumber != target.season) return null;
    for (final e in loaded.episodes) {
      if (e.episodeNumber != target.episode) continue;
      final aired = DateTime.tryParse(e.airDate ?? '');
      return aired != null && !aired.isAfter(DateTime.now());
    }
    return false;
  }

  /// Resume an episode from where it was left only if it is the one the
  /// history entry points at.
  int _resumePointFor(Episode e) {
    final r = _resume;
    if (r == null || r.completed) return 0;
    if (r.seasonNumber == e.seasonNumber &&
        r.episodeNumber == e.episodeNumber) {
      return r.progressSeconds;
    }
    return 0;
  }

  Widget _watchlistButton() => TvButton(
    key: const ValueKey('watchlist'),
    label: 'My List',
    icon: _inWatchlist ? Icons.check_rounded : Icons.add_rounded,
    onPressed: _toggleWatchlist,
  );

  List<Widget> _commonSections({
    required List<_CastEntry> cast,
    required List<({int id, String name})> genres,
  }) {
    return [
      if (_similar.isNotEmpty)
        TvRailSection(
          key: const ValueKey('similar'),
          title: 'More Like This',
          child: TvPosterRail(
            count: _similar.length,
            cardBuilder: (context, i) {
              final r = _similar[i];
              return TvPosterCard(
                posterPath: r.posterPath,
                title: r.title ?? r.name,
                onPressed: () => _openTitle(r),
              );
            },
          ),
        ),
      if (cast.isNotEmpty)
        TvRailSection(
          key: const ValueKey('cast'),
          title: 'Cast',
          child: TvRail(
            itemCount: cast.length,
            itemExtent: 96.s(context),
            height: 142.s(context),
            itemBuilder:
                (context, i) => _CastTile(
                  actor: cast[i],
                  onPressed: () => _openPerson(cast[i]),
                ),
          ),
        ),
      if (genres.isNotEmpty)
        TvSection(
          key: const ValueKey('genres'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const TvSectionTitle(title: 'Genres'),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  kTvGutter.s(context),
                  10.s(context),
                  kTvGutter.s(context),
                  10.s(context),
                ),
                child: TvRowFocusGroup(
                  child: Wrap(
                    spacing: 8.s(context),
                    runSpacing: 8.s(context),
                    children: [
                      for (final g in genres)
                        TvChip(
                          label: g.name,
                          onPressed: () => _openGenre(g.id, g.name),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildPage({
    required String? backdropPath,
    required Widget hero,
    required List<Widget> sections,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        TvBillboardBackdrop(path: backdropPath),
        // Dim the artwork as the page scrolls down into its rails.
        AnimatedBuilder(
          animation: _scroll,
          builder: (context, _) {
            final offset = _scroll.hasClients ? _scroll.offset : 0.0;
            final alpha = (offset / 260.s(context)).clamp(0.0, 0.86);
            if (alpha == 0) return const SizedBox.shrink();
            return ColoredBox(color: kDeepBlack.withValues(alpha: alpha));
          },
        ),
        ListView(
          controller: _scroll,
          padding: EdgeInsets.only(bottom: 90.s(context)),
          children: [
            TvSection(key: const ValueKey('hero'), alignment: 0, child: hero),
            // Keyed by section: "More Like This" can arrive after the user
            // has already moved down the page, and must not shift (and so
            // rebuild) the section that currently holds focus.
            for (final section in sections)
              Padding(
                key: section.key,
                padding: EdgeInsets.only(top: 6.s(context)),
                child: section,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildError() {
    return TvMessage(
      icon: Icons.cloud_off_rounded,
      title: "Couldn't load this title",
      detail: 'The source may be busy — try again.',
      actions: [
        TvButton(
          label: _retrying ? 'Retrying…' : 'Retry',
          icon: Icons.refresh_rounded,
          autofocus: true,
          onPressed:
              _retrying ? () {} : () => _loadDetails(keepErrorCard: true),
        ),
        TvButton(
          label: 'Go Back',
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  static String? _year(String? date) =>
      (date != null && date.length >= 4) ? date.substring(0, 4) : null;

  static String _formatRuntime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String _formatProgress(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m in' : '${m}m in';
  }
}

// ============== HERO ==============

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.kind,
    required this.title,
    required this.meta,
    required this.credits,
    required this.actions,
    this.tagline,
    this.overview,
    this.rating,
  });

  final String kind;
  final String title;
  final String? tagline;
  final String? overview;
  final double? rating;
  final List<String> meta;

  /// (label, value) pairs such as ('Starring', 'A, B, C').
  final List<(String, String)> credits;

  /// Null while the full details are still loading.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shadow = [
      Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 12),
    ];
    final tagline = this.tagline;
    final overview = this.overview;
    final actions = this.actions;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: size.height * 0.76),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          kTvGutter.s(context),
          64.s(context),
          kTvGutter.s(context),
          18.s(context),
        ),
        child: SizedBox(
          width: size.width * 0.48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 3.s(context),
                    height: 12.s(context),
                    color: kNetflixRed,
                  ),
                  SizedBox(width: 8.s(context)),
                  Text(
                    kind,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 10.5.s(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3.s(context),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.s(context)),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 40.s(context),
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  letterSpacing: -0.5.s(context),
                  shadows: shadow,
                ),
              ),
              SizedBox(height: 10.s(context)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvMetaLine(rating: rating, items: meta),
                  SizedBox(width: 10.s(context)),
                  const _QualityTag(label: 'HD'),
                ],
              ),
              if (tagline != null && tagline.isNotEmpty) ...[
                SizedBox(height: 12.s(context)),
                Text(
                  tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14.s(context),
                    fontStyle: FontStyle.italic,
                    shadows: shadow,
                  ),
                ),
              ],
              if (overview != null && overview.isNotEmpty) ...[
                SizedBox(height: 10.s(context)),
                Text(
                  overview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 13.s(context),
                    height: 1.45,
                    shadows: shadow,
                  ),
                ),
              ],
              SizedBox(height: 18.s(context)),
              if (actions == null)
                // A route with nothing focusable swallows the remote, so the
                // loading hero keeps a placeholder in the ring until the real
                // actions replace it and take the focus back.
                // A route with nothing focusable swallows the remote, so the
                // skeleton itself holds the focus until the real actions
                // mount and take it back. Deliberately a bare Focus and not a
                // TvButton: a solid-white "Play" that does nothing when
                // pressed is worse than a dead D-pad.
                Focus(
                  autofocus: true,
                  child: TvPulse(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TvSkeletonBox(
                          width: 96.s(context),
                          height: 36.s(context),
                        ),
                        SizedBox(width: 10.s(context)),
                        TvSkeletonBox(
                          width: 110.s(context),
                          height: 36.s(context),
                        ),
                      ],
                    ),
                  ),
                )
              else
                TvRowFocusGroup(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) SizedBox(width: 10.s(context)),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              if (credits.isNotEmpty) ...[
                SizedBox(height: 16.s(context)),
                for (final (label, value) in credits)
                  Padding(
                    padding: EdgeInsets.only(bottom: 3.s(context)),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$label:  ',
                            style: const TextStyle(color: kTextGrey),
                          ),
                          TextSpan(text: value),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11.5.s(context),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityTag extends StatelessWidget {
  const _QualityTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 5.s(context),
        vertical: 1.s(context),
      ),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3.s(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 9.5.s(context),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============== EPISODES ==============

const double _episodeWidth = 196;
const double _episodeGap = 14;

class _EpisodesSection extends StatefulWidget {
  const _EpisodesSection({
    super.key,
    required this.store,
    required this.tv,
    required this.resume,
    required this.pendingSeason,
    required this.onSeasonFocused,
    required this.onSeasonPressed,
    required this.onPlay,
  });

  final TvDetailStore store;
  final TvDetail tv;
  final HistoryItem? resume;
  final int? pendingSeason;
  final ValueChanged<int> onSeasonFocused;
  final ValueChanged<int> onSeasonPressed;
  final ValueChanged<Episode> onPlay;

  @override
  State<_EpisodesSection> createState() => _EpisodesSectionState();
}

class _EpisodesSectionState extends State<_EpisodesSection> {
  static double _railHeight(BuildContext context) => 212.s(context);

  /// Wraps the episode rail and OUTLIVES it. The rail itself is keyed by
  /// season, so when a new season's payload lands the whole subtree — and
  /// every episode FocusNode in it — is replaced; this node is what lets us
  /// notice that focus was inside at the time and put it back.
  final FocusNode _rail = FocusNode(
    debugLabel: 'episodeRail',
    skipTraversal: true,
    canRequestFocus: false,
  );
  int? _builtSeason;

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  void _refocusRailNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final node in _rail.traversalDescendants) {
        if (node.canRequestFocus) {
          node.requestFocus();
          return;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final selected =
            widget.pendingSeason ?? widget.store.selectedSeasonNumber;
        final single = widget.tv.seasons.length == 1;
        return TvSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TvSectionTitle(
                title: 'Episodes',
                trailing:
                    single
                        ? (widget.tv.seasons.first.name ??
                            'Season ${widget.tv.seasons.first.seasonNumber}')
                        : null,
              ),
              if (widget.tv.seasons.length > 1)
                TvFlowRail(
                  height: 48.s(context),
                  children: [
                    for (final s in widget.tv.seasons)
                      TvChip(
                        label: s.name ?? 'Season ${s.seasonNumber}',
                        selected: s.seasonNumber == selected,
                        onFocusChange: (f) {
                          if (f) widget.onSeasonFocused(s.seasonNumber);
                        },
                        onPressed: () => widget.onSeasonPressed(s.seasonNumber),
                      ),
                  ],
                ),
              _buildEpisodes(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEpisodes(BuildContext context) {
    final height = _railHeight(context);
    final season = widget.store.selectedSeason;
    if (season == null) {
      if (!widget.store.isSeasonLoading && !widget.store.isLoading) {
        return _note(context, height, "Couldn't load episodes");
      }
      return SizedBox(height: height, child: const _EpisodesSkeleton());
    }

    // Drop episodes that haven't aired yet — TMDB lists future episodes in
    // the season payload but they obviously can't be played.
    final now = DateTime.now();
    final episodes =
        season.episodes.where((ep) {
          final aired = DateTime.tryParse(ep.airDate ?? '');
          return aired != null && !aired.isAfter(now);
        }).toList();

    // Still showing the previous season while the newly picked one loads.
    final stale =
        widget.store.isSeasonLoading ||
        widget.pendingSeason != null &&
            widget.pendingSeason != season.seasonNumber;

    if (episodes.isEmpty) {
      return _note(context, height, 'No episodes have aired yet');
    }
    final r = widget.resume;
    // Focus was in the rail we are about to replace — restore it once the
    // new season's cards exist, otherwise the highlight is thrown back up to
    // the season chips (or Play) mid-browse.
    if (_builtSeason != null &&
        _builtSeason != season.seasonNumber &&
        _rail.hasFocus) {
      _refocusRailNextFrame();
    }
    _builtSeason = season.seasonNumber;
    return AnimatedOpacity(
      opacity: stale ? 0.35 : 1,
      duration: TvMotion.focus,
      child: Focus(
        focusNode: _rail,
        canRequestFocus: false,
        skipTraversal: true,
        child: TvFadeIn(
          key: ValueKey(season.seasonNumber),
          child: TvRail(
            storageId: 'episodes-${widget.tv.id}-${season.seasonNumber}',
            itemCount: episodes.length,
            itemExtent: (_episodeWidth + _episodeGap).s(context),
            height: height,
            itemBuilder: (context, i) {
              final e = episodes[i];
              final inProgress =
                  r != null &&
                  !r.completed &&
                  r.seasonNumber == e.seasonNumber &&
                  r.episodeNumber == e.episodeNumber;
              return _EpisodeCard(
                episode: e,
                progress: inProgress ? r.progressFraction : null,
                onPressed: () => widget.onPlay(e),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _note(BuildContext context, double height, String text) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(
          left: kTvGutter.s(context),
          top: 20.s(context),
        ),
        child: Text(
          text,
          style: TextStyle(color: kTextGrey, fontSize: 13.s(context)),
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.onPressed,
    this.progress,
  });

  final Episode episode;
  final VoidCallback onPressed;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final width = _episodeWidth.s(context);
    final runtime = episode.runtime;
    final overview = episode.overview;
    return TvFocusable(
      onPressed: onPressed,
      builder: (context, focused) {
        return SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocusFrame(
                focused: focused,
                radius: 5.s(context),
                ringWidth: 2.5.s(context),
                scale: 1.05,
                child: SizedBox(
                  width: width,
                  height: width * 9 / 16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TvImage(
                        path: episode.stillPath,
                        kind: TmdbImageKind.still,
                        width: width,
                        fallback: Container(
                          color: kSurfaceHi,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.tv_rounded,
                            color: Colors.white24,
                            size: 34.s(context),
                          ),
                        ),
                      ),
                      Center(
                        child: AnimatedOpacity(
                          opacity: focused ? 1 : 0,
                          duration: TvMotion.focus,
                          curve: TvMotion.curve,
                          child: Container(
                            width: 34.s(context),
                            height: 34.s(context),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22.s(context),
                            ),
                          ),
                        ),
                      ),
                      if (progress != null && progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: TvProgressBar(value: progress!),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10.s(context)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${episode.episodeNumber}. '
                      '${episode.name ?? 'Episode ${episode.episodeNumber}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            focused
                                ? kTextWhite
                                : Colors.white.withValues(alpha: 0.82),
                        fontSize: 12.5.s(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (runtime != null && runtime > 0) ...[
                    SizedBox(width: 6.s(context)),
                    Text(
                      '${runtime}m',
                      style: TextStyle(
                        color: kTextGrey,
                        fontSize: 11.s(context),
                      ),
                    ),
                  ],
                ],
              ),
              if (overview != null && overview.isNotEmpty) ...[
                SizedBox(height: 3.s(context)),
                Text(
                  overview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: kTextGrey.withValues(alpha: focused ? 1 : 0.75),
                    fontSize: 10.5.s(context),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EpisodesSkeleton extends StatelessWidget {
  const _EpisodesSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = _episodeWidth.s(context);
    return TvPulse(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: double.infinity,
        child: Padding(
          padding: EdgeInsets.only(
            left: kTvGutter.s(context),
            top: 12.s(context),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: EdgeInsets.only(right: _episodeGap.s(context)),
                  child: TvSkeletonBox(width: width, height: width * 9 / 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== CAST ==============

class _CastTile extends StatelessWidget {
  const _CastTile({required this.actor, required this.onPressed});

  final _CastEntry actor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = 74.s(context);
    final character = actor.character;
    return TvFocusable(
      onPressed: onPressed,
      builder: (context, focused) {
        return SizedBox(
          width: 84.s(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocusFrame(
                focused: focused,
                circle: true,
                ringWidth: 2.5.s(context),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: TvImage(
                    path: actor.profilePath,
                    kind: TmdbImageKind.profile,
                    width: size,
                    alignment: Alignment.topCenter,
                    fallback: Container(
                      color: kSurfaceHi,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.person_rounded,
                        color: Colors.white24,
                        size: 36.s(context),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10.s(context)),
              Text(
                actor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      focused
                          ? kTextWhite
                          : Colors.white.withValues(alpha: 0.85),
                  fontSize: 11.5.s(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (character != null && character.isNotEmpty)
                Text(
                  character,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTextGrey, fontSize: 10.s(context)),
                ),
            ],
          ),
        );
      },
    );
  }
}
