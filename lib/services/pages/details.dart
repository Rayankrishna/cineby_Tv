import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/models/tv_detail_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/webview.dart';
import 'package:cineby_tv/services/stream_servers.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/stores/tv_detail_store.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart';

class MovieDetailsPage extends StatefulWidget {
  final String movieId;
  final String mediaType; // 'movie' | 'tv'

  const MovieDetailsPage({
    super.key,
    required this.movieId,
    this.mediaType = 'movie',
  });

  @override
  State<MovieDetailsPage> createState() => _MovieDetailsPageState();
}

class _MovieDetailsPageState extends State<MovieDetailsPage> {
  final SearchStore _movieStore = SearchStore();
  final TvDetailStore _tvStore = TvDetailStore();

  HistoryItem? _resume;
  bool _inWatchlist = false;
  bool _checkingSource = false;

  // Which stream provider to use. null = Auto (probe for the first reachable
  // one); a non-null value is an explicit user choice used as-is.
  StreamServer? _selectedServer;

  int get _tmdbId => int.tryParse(widget.movieId) ?? 0;
  bool get _isTv => widget.mediaType == 'tv';

  @override
  void initState() {
    super.initState();
    if (_isTv) {
      _tvStore.fetchTvDetail(_tmdbId);
      historyStore.latestForShow(_tmdbId).then((h) {
        if (mounted) setState(() => _resume = h);
      });
    } else {
      _movieStore.fetchMovieDetails(widget.movieId);
      historyStore.latestForMovie(_tmdbId).then((h) {
        if (mounted) setState(() => _resume = h);
      });
    }
    watchlistStore.checkContains(_tmdbId, widget.mediaType).then((in_) {
      if (mounted) setState(() => _inWatchlist = in_);
    });
    loadSelectedServer().then((s) {
      if (mounted) setState(() => _selectedServer = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      body: _isTv ? _buildTv(context) : _buildMovie(context),
    );
  }

  // ============== MOVIE ==============
  Widget _buildMovie(BuildContext context) {
    return Observer(builder: (_) {
      if (_movieStore.isLoading) {
        return const Center(child: CircularProgressIndicator(color: kNetflixRed));
      }
      final movie = _movieStore.movieDetails;
      if (movie == null) {
        return _ErrorState(
          onBack: () => Navigator.pop(context),
          onRetry: () => _movieStore.fetchMovieDetails(widget.movieId),
        );
      }
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _HeroHeader(
              backdropPath: movie.backdropPath,
              title: movie.title ?? 'Untitled',
              tagline: movie.tagline,
              year: movie.releaseDate?.split('-').first,
              runtime: movie.runtime != null ? '${movie.runtime}m' : null,
              overview: movie.overview,
              voteAverage: movie.voteAverage,
              actions: Opacity(
                // Dim the action row while the pre-flight reachability
                // probe runs so the user sees something is happening.
                opacity: _checkingSource ? 0.5 : 1.0,
                child: _buildActions(
                onPlay: () => _playMovie(),
                onResume: _resume != null && !(_resume!.completed)
                    ? () => _playMovie(seekTo: _resume!.progressSeconds)
                    : null,
                resumeSeconds: _resume?.progressSeconds,
              ),
              ),
            ),
          ),
          if (movie.credits?.cast != null && movie.credits!.cast!.isNotEmpty) ...[
            SliverToBoxAdapter(child: _sectionTitle(context, 'Cast')),
            SliverToBoxAdapter(child: _buildCast(context, movie.credits!.cast!)),
          ],
          SliverPadding(padding: EdgeInsets.only(bottom: 60.s(context))),
        ],
      );
    });
  }

  // ============== TV ==============
  Widget _buildTv(BuildContext context) {
    return Observer(builder: (_) {
      if (_tvStore.isLoading) {
        return const Center(child: CircularProgressIndicator(color: kNetflixRed));
      }
      final tv = _tvStore.tvDetail;
      if (tv == null) {
        return _ErrorState(
          onBack: () => Navigator.pop(context),
          onRetry: () => _tvStore.fetchTvDetail(_tmdbId),
        );
      }
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _HeroHeader(
              backdropPath: tv.backdropPath,
              title: tv.name ?? 'Untitled',
              tagline: tv.tagline,
              year: tv.firstAirDate?.split('-').first,
              runtime: tv.numberOfSeasons != null
                  ? '${tv.numberOfSeasons} season${tv.numberOfSeasons == 1 ? '' : 's'}'
                  : null,
              overview: tv.overview,
              voteAverage: tv.voteAverage,
              actions: Opacity(
                // Dim the action row while the pre-flight reachability
                // probe runs so the user sees something is happening.
                opacity: _checkingSource ? 0.5 : 1.0,
                child: _buildActions(
                onPlay: () => _playFirstAvailableEpisode(tv),
                onResume: _resume != null
                    ? () => _playEpisode(
                          tv,
                          _resume!.seasonNumber ?? 1,
                          _resume!.episodeNumber ?? 1,
                          seekTo: _resume!.progressSeconds,
                        )
                    : null,
                resumeSeconds: _resume?.progressSeconds,
                resumeBadge: _resume != null && _resume!.mediaType == 'tv'
                    ? 'S${_resume!.seasonNumber} • E${_resume!.episodeNumber}'
                    : null,
              ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _sectionTitle(context, 'Episodes')),
          SliverToBoxAdapter(child: _EpisodePicker(store: _tvStore, tv: tv, onPlay: _playEpisode)),
          if (tv.cast.isNotEmpty) ...[
            SliverToBoxAdapter(child: _sectionTitle(context, 'Cast')),
            SliverToBoxAdapter(child: _buildCastTv(context, tv.cast)),
          ],
          SliverPadding(padding: EdgeInsets.only(bottom: 60.s(context))),
        ],
      );
    });
  }

  // ============== ACTIONS ==============
  Widget _buildActions({
    required VoidCallback onPlay,
    VoidCallback? onResume,
    int? resumeSeconds,
    String? resumeBadge,
  }) {
    return Builder(builder: (context) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (onResume != null) ...[
                _ActionButton(
                  label: 'Resume${resumeBadge != null ? "  $resumeBadge" : ""}',
                  icon: Icons.play_arrow,
                  isPrimary: true,
                  autofocus: true,
                  onPressed: onResume,
                  subLabel:
                      resumeSeconds != null ? _fmtSeconds(resumeSeconds) : null,
                ),
                SizedBox(width: 16.s(context)),
                _ActionButton(
                  label: 'Play from start',
                  icon: Icons.replay,
                  isPrimary: false,
                  onPressed: onPlay,
                ),
              ] else
                _ActionButton(
                  label: _isTv ? 'Watch S1·E1' : 'Play',
                  icon: Icons.play_arrow,
                  isPrimary: true,
                  autofocus: true,
                  onPressed: onPlay,
                ),
              SizedBox(width: 16.s(context)),
              _ActionButton(
                label: _inWatchlist ? 'In Watchlist' : 'Add to Watchlist',
                icon: _inWatchlist ? Icons.bookmark : Icons.bookmark_border,
                isPrimary: false,
                onPressed: _toggleWatchlist,
              ),
            ],
          ),
          SizedBox(height: 22.s(context)),
          _ServerSelector(
            selected: _selectedServer,
            onSelected: (s) {
              setState(() => _selectedServer = s);
              saveSelectedServer(s); // persist the choice across the app
            },
          ),
        ],
      );
    });
  }

  String _fmtSeconds(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m in';
    return '${m}m in';
  }

  Future<void> _toggleWatchlist() async {
    String? title, poster;
    if (_isTv) {
      title = _tvStore.tvDetail?.name;
      poster = _tvStore.tvDetail?.posterPath;
    } else {
      title = _movieStore.movieDetails?.title;
      poster = _movieStore.movieDetails?.posterPath;
    }
    await watchlistStore.toggle(
      tmdbId: _tmdbId,
      mediaType: widget.mediaType,
      title: title,
      posterPath: poster,
    );
    final now = await watchlistStore.checkContains(_tmdbId, widget.mediaType);
    if (mounted) setState(() => _inWatchlist = now);
  }

  void _playMovie({int seekTo = 0}) {
    _doPlayMovie(seekTo: seekTo);
  }

  /// Resolve which provider to launch: an explicit user pick (`_selectedServer`)
  /// is used as-is; otherwise probe providers in order for the first reachable
  /// one. Returns null (and shows a message) when nothing is reachable.
  Future<StreamServer?> _resolveServer({
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final picked = _selectedServer;
    if (picked != null) return picked;
    setState(() => _checkingSource = true);
    final server = await findReachableServer(
      tmdbId: _tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    if (!mounted) return null;
    setState(() => _checkingSource = false);
    if (server == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1F1E26),
          content: Text(
            'No sources are reachable right now. '
            'Check your connection and try again.',
          ),
        ),
      );
    }
    return server;
  }

  Future<void> _doPlayMovie({int seekTo = 0}) async {
    final m = _movieStore.movieDetails;
    final server = await _resolveServer(mediaType: 'movie');
    if (server == null || !mounted) return;
    final url = server.buildUrl(_tmdbId, 'movie', null, null);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyWidget(
          url: url,
          tmdbId: _tmdbId,
          mediaType: 'movie',
          initialProgressSeconds: seekTo,
          title: m?.title,
          posterPath: m?.posterPath,
          backdropPath: m?.backdropPath,
        ),
      ),
    );
  }

  void _playFirstAvailableEpisode(TvDetail tv) {
    final season = tv.seasons.isNotEmpty ? tv.seasons.first.seasonNumber : 1;
    _playEpisode(tv, season, 1);
  }

  void _playEpisode(TvDetail tv, int season, int episode, {int seekTo = 0}) {
    _doPlayEpisode(tv, season, episode, seekTo: seekTo);
  }

  Future<void> _doPlayEpisode(TvDetail tv, int season, int episode,
      {int seekTo = 0}) async {
    final server = await _resolveServer(
      mediaType: 'tv',
      seasonNumber: season,
      episodeNumber: episode,
    );
    if (server == null || !mounted) return;
    final url = server.buildUrl(_tmdbId, 'tv', season, episode);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyWidget(
          url: url,
          tmdbId: _tmdbId,
          mediaType: 'tv',
          seasonNumber: season,
          episodeNumber: episode,
          initialProgressSeconds: seekTo,
          title: tv.name,
          posterPath: tv.posterPath,
          backdropPath: tv.backdropPath,
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: EdgeInsets.only(
          left: 60.s(context),
          top: 40.s(context),
          bottom: 16.s(context),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: kTextWhite,
            fontSize: 24.s(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _buildCast(BuildContext context, List cast) {
    return SizedBox(
      height: 220.s(context),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 50.s(context)),
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        itemBuilder: (ctx, i) => _CastCardDyn(actor: cast[i]),
      ),
    );
  }

  Widget _buildCastTv(BuildContext context, List<CastMember> cast) {
    return SizedBox(
      height: 220.s(context),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 50.s(context)),
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        itemBuilder: (ctx, i) => _CastCard(actor: cast[i]),
      ),
    );
  }
}

// ============== SERVER SELECTOR ==============
class _ServerSelector extends StatelessWidget {
  final StreamServer? selected; // null = Auto
  final ValueChanged<StreamServer?> onSelected;
  const _ServerSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.dns_outlined, color: kTextGrey, size: 15.s(context)),
            SizedBox(width: 6.s(context)),
            Text(
              'SOURCE',
              style: TextStyle(
                color: kTextGrey,
                fontSize: 12.s(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 2.s(context),
              ),
            ),
          ],
        ),
        SizedBox(height: 10.s(context)),
        Wrap(
          spacing: 10.s(context),
          runSpacing: 10.s(context),
          children: [
            _ServerChip(
              label: 'Auto',
              selected: selected == null,
              onSelected: () => onSelected(null),
            ),
            for (final s in streamServers)
              _ServerChip(
                label: s.name,
                selected: selected?.name == s.name,
                onSelected: () => onSelected(s),
              ),
          ],
        ),
      ],
    );
  }
}

class _ServerChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  const _ServerChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onSelected,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: 16.s(context),
              vertical: 8.s(context),
            ),
            decoration: BoxDecoration(
              color: selected
                  ? kNetflixRed
                  : (focused ? Colors.white24 : Colors.white.withOpacity(0.10)),
              borderRadius: BorderRadius.circular(20.s(context)),
              border: Border.all(
                color: focused ? kTextWhite : Colors.transparent,
                width: 2.s(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 14.s(context), color: kTextWhite),
                  SizedBox(width: 6.s(context)),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: kTextWhite,
                    fontSize: 13.s(context),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ============== HERO ==============
class _HeroHeader extends StatelessWidget {
  final String? backdropPath;
  final String title;
  final String? tagline;
  final String? year;
  final String? runtime;
  final String? overview;
  final double? voteAverage;
  final Widget actions;

  const _HeroHeader({
    this.backdropPath,
    required this.title,
    this.tagline,
    this.year,
    this.runtime,
    this.overview,
    this.voteAverage,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.0),
                    Colors.black.withOpacity(0.3),
                    kDeepBlack,
                  ],
                  stops: const [0, 0.4, 0.9],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: backdropPath != null
                  ? Image.network('$imgOriginal$backdropPath', fit: BoxFit.cover)
                  : Container(color: kSurfaceGrey),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    kDeepBlack.withOpacity(0.85),
                    kDeepBlack.withOpacity(0.35),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              60.s(context),
              80.s(context),
              60.s(context),
              40.s(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: kTextWhite,
                    fontSize: 56.s(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.s(context),
                    height: 1.0,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.7),
                        blurRadius: 14.s(context),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.s(context)),
                Row(
                  children: [
                    if (year != null)
                      Text(year!, style: TextStyle(color: kTextGrey, fontSize: 16.s(context))),
                    if (year != null) SizedBox(width: 14.s(context)),
                    if (runtime != null)
                      Text(runtime!,
                          style: TextStyle(color: kTextGrey, fontSize: 16.s(context))),
                    if (runtime != null) SizedBox(width: 14.s(context)),
                    if (voteAverage != null && voteAverage! > 0)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.s(context),
                          vertical: 2.s(context),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15),
                          borderRadius: BorderRadius.circular(4.s(context)),
                        ),
                        child: Text(
                          '★ ${voteAverage!.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: kDeepBlack,
                            fontSize: 12.s(context),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    SizedBox(width: 14.s(context)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.s(context),
                        vertical: 1.s(context),
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: kTextGrey.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(4.s(context)),
                      ),
                      child: Text(
                        'HD',
                        style: TextStyle(
                          color: kTextWhite.withOpacity(0.8),
                          fontSize: 11.s(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (tagline != null && tagline!.isNotEmpty) ...[
                  SizedBox(height: 18.s(context)),
                  Text(
                    tagline!,
                    style: TextStyle(
                      color: kTextWhite.withOpacity(0.85),
                      fontSize: 20.s(context),
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
                SizedBox(height: 18.s(context)),
                if (overview != null)
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.48,
                    child: Text(
                      overview!,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kTextWhite.withOpacity(0.9),
                        fontSize: 16.s(context),
                        height: 1.55,
                      ),
                    ),
                  ),
                SizedBox(height: 32.s(context)),
                actions,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============== ACTION BUTTON ==============
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool autofocus;
  final String? subLabel;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    this.autofocus = false,
    this.subLabel,
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
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal: 26.s(context),
              vertical: 12.s(context),
            ),
            decoration: BoxDecoration(
              color: isPrimary
                  ? (focused ? Colors.white : Colors.white.withOpacity(0.92))
                  : (focused ? Colors.white24 : Colors.white.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(4.s(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isPrimary ? Colors.black : Colors.white,
                  size: 24.s(context),
                ),
                SizedBox(width: 8.s(context)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isPrimary ? Colors.black : Colors.white,
                        fontSize: 16.s(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subLabel != null)
                      Text(
                        subLabel!,
                        style: TextStyle(
                          color: isPrimary ? Colors.black54 : Colors.white60,
                          fontSize: 10.s(context),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ============== EPISODE PICKER ==============
class _EpisodePicker extends StatelessWidget {
  final TvDetailStore store;
  final TvDetail tv;
  final void Function(TvDetail tv, int season, int episode, {int seekTo}) onPlay;

  const _EpisodePicker({required this.store, required this.tv, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 60.s(context)),
      child: SizedBox(
        height: 320.s(context),
        child: FocusTraversalGroup(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200.s(context),
                child: Observer(builder: (_) {
                  return ListView.builder(
                    itemCount: tv.seasons.length,
                    itemBuilder: (ctx, i) {
                      final s = tv.seasons[i];
                      final sel = store.selectedSeasonNumber == s.seasonNumber;
                      return _SeasonRow(
                        label: s.name ?? 'Season ${s.seasonNumber}',
                        episodes: s.episodeCount,
                        selected: sel,
                        onFocus: () => store.fetchSeason(tv.id, s.seasonNumber),
                      );
                    },
                  );
                }),
              ),
              SizedBox(width: 16.s(context)),
              Expanded(
                child: Observer(builder: (_) {
                  if (store.isSeasonLoading || store.selectedSeason == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: kNetflixRed),
                    );
                  }
                  final eps = store.selectedSeason!.episodes;
                  if (eps.isEmpty) {
                    return Center(
                      child: Text('No episodes',
                          style: TextStyle(color: kTextGrey, fontSize: 14.s(context))),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: eps.length,
                    separatorBuilder: (_, __) => SizedBox(width: 16.s(context)),
                    itemBuilder: (ctx, i) {
                      final e = eps[i];
                      return _EpisodeCard(
                        episode: e,
                        onPlay: () => onPlay(tv, e.seasonNumber, e.episodeNumber),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonRow extends StatelessWidget {
  final String label;
  final int? episodes;
  final bool selected;
  final VoidCallback onFocus;
  const _SeasonRow({
    required this.label,
    this.episodes,
    required this.selected,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        if (f) onFocus();
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return Container(
          margin: EdgeInsets.symmetric(vertical: 4.s(context)),
          padding: EdgeInsets.symmetric(
            horizontal: 14.s(context),
            vertical: 12.s(context),
          ),
          decoration: BoxDecoration(
            color: focused ? kNetflixRed : (selected ? kSurfaceHi : Colors.transparent),
            borderRadius: BorderRadius.circular(8.s(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 14.s(context),
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (episodes != null)
                Text('$episodes episodes',
                    style: TextStyle(color: Colors.white60, fontSize: 11.s(context))),
            ],
          ),
        );
      }),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final Episode episode;
  final VoidCallback onPlay;
  const _EpisodeCard({required this.episode, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onPlay();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPlay,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 260.s(context),
            transform: focused ? (Matrix4.identity()..scale(1.04)) : Matrix4.identity(),
            decoration: BoxDecoration(
              color: kSurfaceGrey,
              borderRadius: BorderRadius.circular(10.s(context)),
              border: Border.all(
                color: focused ? kTextWhite : Colors.transparent,
                width: 3.s(context),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.s(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: episode.stillPath != null
                        ? Image.network('$imgW300${episode.stillPath}', fit: BoxFit.cover)
                        : Container(
                            color: kSurfaceHi,
                            alignment: Alignment.center,
                            child: Icon(Icons.tv, color: Colors.white24, size: 48.s(context)),
                          ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(10.s(context)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'E${episode.episodeNumber} · ${episode.name ?? "Episode ${episode.episodeNumber}"}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kTextWhite,
                            fontSize: 13.s(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (episode.runtime != null)
                          Text('${episode.runtime}m',
                              style: TextStyle(color: kTextGrey, fontSize: 11.s(context))),
                      ],
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

// ============== CAST CARDS ==============
class _CastCard extends StatelessWidget {
  final CastMember actor;
  const _CastCard({required this.actor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.s(context)),
      child: SizedBox(
        width: 120.s(context),
        child: Column(
          children: [
            Container(
              height: 140.s(context),
              width: 120.s(context),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.s(context)),
                color: kSurfaceGrey,
                image: actor.profilePath != null
                    ? DecorationImage(
                        image: NetworkImage('$imgW200${actor.profilePath}'),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: actor.profilePath == null
                  ? Icon(Icons.person, color: Colors.white24, size: 48.s(context))
                  : null,
            ),
            SizedBox(height: 8.s(context)),
            Text(
              actor.name,
              style: TextStyle(color: kTextWhite, fontSize: 13.s(context)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (actor.character != null)
              Text(
                actor.character!,
                style: TextStyle(color: kTextGrey, fontSize: 11.s(context)),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _CastCardDyn extends StatelessWidget {
  final dynamic actor;
  const _CastCardDyn({required this.actor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.s(context)),
      child: SizedBox(
        width: 120.s(context),
        child: Column(
          children: [
            Container(
              height: 140.s(context),
              width: 120.s(context),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.s(context)),
                color: kSurfaceGrey,
                image: actor.profilePath != null
                    ? DecorationImage(
                        image: NetworkImage('$imgW200${actor.profilePath}'),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: actor.profilePath == null
                  ? Icon(Icons.person, color: Colors.white24, size: 48.s(context))
                  : null,
            ),
            SizedBox(height: 8.s(context)),
            Text(
              actor.name ?? '',
              style: TextStyle(color: kTextWhite, fontSize: 13.s(context)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (actor.character != null)
              Text(
                actor.character ?? '',
                style: TextStyle(color: kTextGrey, fontSize: 11.s(context)),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

// ============== ERROR ==============
class _ErrorState extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onRetry;
  const _ErrorState({required this.onBack, this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, color: kTextGrey, size: 40.s(context)),
          SizedBox(height: 14.s(context)),
          Text(
            "Couldn't load this title",
            style: TextStyle(
              color: kTextWhite,
              fontSize: 18.s(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6.s(context)),
          Text(
            'The source may be busy — try again.',
            style: TextStyle(color: kTextGrey, fontSize: 13.s(context)),
          ),
          SizedBox(height: 22.s(context)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetry != null) ...[
                _ActionButton(
                  label: 'Retry',
                  icon: Icons.refresh,
                  isPrimary: true,
                  autofocus: true,
                  onPressed: onRetry!,
                ),
                SizedBox(width: 14.s(context)),
              ],
              _ActionButton(
                label: 'Go Back',
                icon: Icons.arrow_back,
                isPrimary: false,
                autofocus: onRetry == null,
                onPressed: onBack,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
