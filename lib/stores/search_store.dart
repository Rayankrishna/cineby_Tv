import 'package:cineby_tv/models/movie_details_model.dart';
import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:dio/dio.dart';
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
      final response = await Dio().get('$searchUrl$query');
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

  @action
  Future<void> fetchTrendingResults() async {
    isLoading = true;
    errorMessage = null;
    try {
      final response = await Dio().get(homeUrl);
      if (response.statusCode == 200) {
        final searchResponse = SearchResponse.fromJson(response.data);
        trendingResults = ObservableList.of(searchResponse.results);
      } else {
        errorMessage = 'Failed to load trending results';
      }
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
      final response = await Dio().get('$movieDetailUrl$id$movieDetailParams');
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
