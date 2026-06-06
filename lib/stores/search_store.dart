import 'package:cineby_tv/models/movie_details_model.dart';
import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:dio/dio.dart';
import 'package:mobx/mobx.dart';

part 'search_store.g.dart';

class SearchStore = _SearchStore with _$SearchStore;

abstract class _SearchStore with Store {
  final Dio _dio = Dio();

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
      final response = await _dio.get('$searchUrl$query');
      if (response.statusCode == 200) {
        final searchResponse = SearchResponse.fromJson(response.data);
        searchResults = ObservableList.of(searchResponse.results);
      } else {
        errorMessage = 'Failed to load results';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  Future<ObservableList<SearchResult>> _fetchList(String url, String mediaTypeFallback) async {
    try {
      final r = await _dio.get(url);
      if (r.statusCode == 200) {
        final sr = SearchResponse.fromJson(r.data);
        // discover/* endpoints don't return media_type; the SearchResult model
        // tolerates null, but downstream code needs it.
        for (final item in sr.results) {
          item.mediaType ??= mediaTypeFallback;
        }
        return ObservableList.of(sr.results);
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
      ]);
      trendingResults = results[0];
      topMovies = results[1];
      topSeries = results[2];
      topAnime = results[3];
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> fetchMovieDetails(String id) async {
    isLoading = true;
    errorMessage = null;
    movieDetails = null;
    try {
      final response = await _dio.get('$movieDetailUrl/$id$movieDetailParams');
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
