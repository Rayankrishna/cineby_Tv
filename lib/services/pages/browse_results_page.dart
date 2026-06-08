import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/services/tmdb_client.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Browse all titles of one TMDB genre. Opened from genre chips on the
/// details page.
class GenreResultsPage extends StatefulWidget {
  final int genreId;
  final String genreName;
  final String mediaType; // 'movie' | 'tv'

  const GenreResultsPage({
    super.key,
    required this.genreId,
    required this.genreName,
    this.mediaType = 'movie',
  });

  @override
  State<GenreResultsPage> createState() => _GenreResultsPageState();
}

class _GenreResultsPageState extends State<GenreResultsPage> {
  Future<List<SearchResult>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SearchResult>> _load() async {
    final url = widget.mediaType == 'tv'
        ? tvByGenreUrl(widget.genreId)
        : movieByGenreUrl(widget.genreId);
    final res = await tmdbDio.get(url);
    final list = SearchResponse.fromJson(res.data).results;
    final now = DateTime.now();
    return list.where((r) {
      final d = r.releaseDate ?? r.firstAirDate;
      if (d == null || d.isEmpty) return false;
      final parsed = DateTime.tryParse(d);
      if (parsed == null) return false;
      return !parsed.isAfter(now);
    }).map((r) {
      r.mediaType ??= widget.mediaType;
      return r;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      appBar: AppBar(
        backgroundColor: kDeepBlack,
        elevation: 0,
        title: Text(widget.genreName,
            style: TextStyle(color: kTextWhite, fontSize: 22.s(context))),
      ),
      body: _ResultsBody(future: _future!, defaultMediaType: widget.mediaType),
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
  Future<List<SearchResult>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

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

    final movies = (responses[0].data['cast'] as List<dynamic>? ?? [])
        .map((e) => toResult(e as Map<String, dynamic>, 'movie'))
        .whereType<SearchResult>()
        .toList();
    final tv = (responses[1].data['cast'] as List<dynamic>? ?? [])
        .map((e) => toResult(e as Map<String, dynamic>, 'tv'))
        .whereType<SearchResult>()
        .toList();
    final merged = [...movies, ...tv]
      ..sort((a, b) => (b.voteCount ?? 0).compareTo(a.voteCount ?? 0));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      appBar: AppBar(
        backgroundColor: kDeepBlack,
        elevation: 0,
        title: Text(widget.personName,
            style: TextStyle(color: kTextWhite, fontSize: 22.s(context))),
      ),
      body: _ResultsBody(future: _future!, defaultMediaType: 'movie'),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  final Future<List<SearchResult>> future;
  final String defaultMediaType;
  const _ResultsBody({required this.future, required this.defaultMediaType});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SearchResult>>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: kNetflixRed),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(24.s(context)),
              child: Text(
                'Couldn\'t load — ${snap.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextGrey, fontSize: 14.s(context)),
              ),
            ),
          );
        }
        final items = (snap.data ?? const <SearchResult>[])
            .where((r) => r.posterPath != null)
            .toList();
        if (items.isEmpty) {
          return Center(
            child: Text(
              'Nothing released yet.',
              style: TextStyle(color: kTextGrey, fontSize: 14.s(context)),
            ),
          );
        }
        // 6-column grid sized for 1080p TVs; scales with .s(context) for 4K.
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            40.s(context),
            12.s(context),
            40.s(context),
            60.s(context),
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            childAspectRatio: 132 / 198,
            crossAxisSpacing: 14.s(context),
            mainAxisSpacing: 22.s(context),
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final r = items[i];
            return _BrowseCard(
              item: r,
              autofocus: i == 0,
              defaultMediaType: defaultMediaType,
            );
          },
        );
      },
    );
  }
}

class _BrowseCard extends StatefulWidget {
  final SearchResult item;
  final bool autofocus;
  final String defaultMediaType;
  const _BrowseCard({
    required this.item,
    required this.defaultMediaType,
    this.autofocus = false,
  });

  @override
  State<_BrowseCard> createState() => _BrowseCardState();
}

class _BrowseCardState extends State<_BrowseCard> {
  bool _focused = false;

  void _open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsPage(
          movieId: widget.item.id.toString(),
          mediaType: widget.item.mediaType ?? widget.defaultMediaType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          _open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: _focused
              ? (Matrix4.identity()..scale(1.08))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6.s(context)),
            border: Border.all(
              color: _focused ? kNetflixRed : Colors.transparent,
              width: 2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.7),
                      blurRadius: 18.s(context),
                      offset: Offset(0, 8.s(context)),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6.s(context)),
            child: Image.network(
              '$imgW300${widget.item.posterPath}',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: kSurfaceGrey,
                child: Icon(
                  Icons.movie_rounded,
                  color: kTextGrey,
                  size: 32.s(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
