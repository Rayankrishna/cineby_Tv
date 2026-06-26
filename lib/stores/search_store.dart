import 'dart:math';

import 'package:cineby_tv/models/movie_details_model.dart';
import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/tmdb_client.dart';
import 'package:mobx/mobx.dart';

part 'search_store.g.dart';

class SearchStore = _SearchStore with _$SearchStore;

abstract class _SearchStore with Store {
  @observable
  String searchQuery = '';

  @observable
  bool isLoading = false;

  @observable
  ObservableList<SearchResult> searchResults = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> trendingResults = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> topMovies = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> topSeries = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> topAnime = ObservableList<SearchResult>();

  // Genre rows — one observable per genre we surface on home.
  @observable
  ObservableList<SearchResult> actionMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> comedyMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> dramaMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> horrorMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> sciFiMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> romanceMovies = ObservableList<SearchResult>();

  // "For You" — TMDB recommendations seeded from the user's watch history,
  // popularity-ranked.
  @observable
  ObservableList<SearchResult> forYou = ObservableList<SearchResult>();

  @observable
  String? errorMessage;

  @observable
  MovieDetails? movieDetails;

  @action
  Future<void> setSearchQuery(String query) async {
    searchQuery = query;
    if (query.isNotEmpty) {
      await fetchSearchResults(query);
    } else {
      searchResults.clear();
    }
  }

  @action
  Future<void> fetchSearchResults(String query) async {
    isLoading = true;
    errorMessage = null;
    try {
      final response = await tmdbDio.get('$searchUrl$query');
      if (response.statusCode == 200) {
        final searchResponse = SearchResponse.fromJson(response.data);
        var results = searchResponse.results;

        // Filter out noise:
        //  - people (no person page on TV)
        //  - zero-vote entries (TMDB ghost rows)
        //  - dateless entries
        //  - unreleased / unaired titles
        final now = DateTime.now();
        results = results.where((item) {
          if (item.mediaType == 'person') return false;
          if ((item.voteCount ?? 0) == 0) return false;
          final date = item.releaseDate ?? item.firstAirDate;
          if (date == null || date.isEmpty) return false;
          final parsed = DateTime.tryParse(date);
          if (parsed == null) return false;
          return !parsed.isAfter(now);
        }).toList();

        results.sort((a, b) =>
            _score(b, query).compareTo(_score(a, query)));

        searchResults = ObservableList.of(results);
      } else {
        errorMessage = 'Failed to load results';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  /// Relevance score: text match against query (exact > startsWith > contains)
  /// + log(voteCount) + voteAverage. Higher = more relevant.
  double _score(SearchResult r, String query) {
    final q = query.trim().toLowerCase();
    final title = (r.title ?? r.name ?? '').toLowerCase();
    final original = (r.originalTitle ?? r.originalName ?? '').toLowerCase();
    double textScore = 0;
    if (title == q || original == q) {
      textScore = 1000;
    } else if (title.startsWith(q) || original.startsWith(q)) {
      textScore = 500;
    } else if (title.contains(q) || original.contains(q)) {
      textScore = 200;
    }
    final votes = (r.voteCount ?? 0).toDouble();
    final voteScore = votes > 0 ? log(votes) * 8 : 0;
    final avgScore = (r.voteAverage ?? 0) * 4;
    return textScore + voteScore + avgScore;
  }

  Future<ObservableList<SearchResult>> _fetchList(String url, String mediaTypeFallback) async {
    try {
      final r = await tmdbDio.get(url);
      if (r.statusCode == 200) {
        final sr = SearchResponse.fromJson(r.data);
        for (final item in sr.results) {
          item.mediaType ??= mediaTypeFallback;
        }
        // Drop unreleased / dateless rows so the home feed only ever shows
        // things the user can actually watch right now.
        final now = DateTime.now();
        final filtered = sr.results.where((item) {
          final date = item.releaseDate ?? item.firstAirDate;
          if (date == null || date.isEmpty) return false;
          final parsed = DateTime.tryParse(date);
          if (parsed == null) return false;
          return !parsed.isAfter(now);
        }).toList();
        return ObservableList.of(filtered);
      }
    } catch (_) {}
    return ObservableList<SearchResult>();
  }

  @action
  Future<void> fetchTrendingResults() async {
    isLoading = true;
    errorMessage = null;
    try {
      final results = await Future.wait([
        _fetchList(homeUrl, 'movie'),
        _fetchList(topMoviesUrl, 'movie'),
        _fetchList(topSeriesUrl, 'tv'),
        _fetchList(topAnimeUrl, 'tv'),
        _fetchList(movieByGenreUrl(tmdbGenreAction), 'movie'),
        _fetchList(movieByGenreUrl(tmdbGenreComedy), 'movie'),
        _fetchList(movieByGenreUrl(tmdbGenreDrama), 'movie'),
        _fetchList(movieByGenreUrl(tmdbGenreHorror), 'movie'),
        _fetchList(movieByGenreUrl(tmdbGenreSciFi), 'movie'),
      ]);
      trendingResults = results[0];
      topMovies = results[1];
      topSeries = results[2];
      topAnime = results[3];
      actionMovies = results[4];
      comedyMovies = results[5];
      dramaMovies = results[6];
      horrorMovies = results[7];
      sciFiMovies = results[8];
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  /// Build the "For You" rail from the user's watch history. For each of the
  /// most recent [seeds] pull TMDB recommendations, then merge → drop
  /// unreleased → drop already-watched → dedupe → rank by popularity.
  @action
  Future<void> fetchForYou(List<({int tmdbId, String mediaType})> seeds) async {
    if (seeds.isEmpty) {
      forYou = ObservableList<SearchResult>();
      return;
    }
    final seedIds = seeds.map((s) => s.tmdbId).toSet();
    final picks = seeds.take(6).toList();
    try {
      final lists = await Future.wait(
        picks.map((s) async {
          try {
            final res =
                await tmdbDio.get(recommendationsUrl(s.tmdbId, s.mediaType));
            if (res.statusCode != 200) return const <SearchResult>[];
            return SearchResponse.fromJson(res.data).results;
          } catch (_) {
            return const <SearchResult>[];
          }
        }),
      );
      final now = DateTime.now();
      final byId = <int, SearchResult>{};
      for (final list in lists) {
        for (final r in list) {
          if (seedIds.contains(r.id)) continue;
          if (r.posterPath == null) continue;
          final date = r.releaseDate ?? r.firstAirDate;
          if (date == null || date.isEmpty) continue;
          final d = DateTime.tryParse(date);
          if (d == null || d.isAfter(now)) continue;
          byId.putIfAbsent(r.id, () => r);
        }
      }
      final ranked = byId.values.toList()
        ..sort((a, b) {
          final vc = (b.voteCount ?? 0).compareTo(a.voteCount ?? 0);
          if (vc != 0) return vc;
          return (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0);
        });
      forYou = ObservableList.of(ranked.take(20).toList());
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> fetchMovieDetails(String id) async {
    isLoading = true;
    errorMessage = null;
    movieDetails = null;
    try {
      final response = await tmdbDio.get('$movieDetailUrl/$id$movieDetailParams');
      if (response.statusCode == 200) {
        movieDetails = MovieDetails.fromJson(response.data);
      } else {
        errorMessage = 'Failed to load movie details';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }
}
