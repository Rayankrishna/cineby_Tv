import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/services/api_client.dart';
import 'package:mobx/mobx.dart';

part 'history_store.g.dart';

class HistoryStore = _HistoryStore with _$HistoryStore;

abstract class _HistoryStore with Store {
  @observable
  ObservableList<HistoryItem> items = ObservableList<HistoryItem>();

  @observable
  ObservableList<HistoryItem> continueWatching = ObservableList<HistoryItem>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> fetch() async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await apiClient.get('/history');
      if (res.statusCode == 200 && res.data is Map) {
        final list = (res.data['items'] as List? ?? []);
        items = ObservableList.of(list
            .map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      } else {
        errorMessage = 'Failed to load history';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> fetchContinueWatching() async {
    try {
      final res = await apiClient.get('/history/continue-watching');
      if (res.statusCode == 200 && res.data is Map) {
        final list = (res.data['items'] as List? ?? []);
        continueWatching = ObservableList.of(list
            .map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
    } catch (_) {
      // silent — continue watching is best-effort
    }
  }

  Future<HistoryItem?> latestForMovie(int tmdbId) =>
      _latestFor(tmdbId, 'movie');

  Future<HistoryItem?> latestForShow(int tmdbId) =>
      _latestFor(tmdbId, 'tv');

  Future<HistoryItem?> _latestFor(int tmdbId, String mediaType) async {
    try {
      final res = await apiClient.get(
        '/history/$tmdbId',
        query: {'mediaType': mediaType},
      );
      if (res.statusCode == 200 && res.data is Map) {
        final raw = res.data['item'];
        if (raw is Map) {
          return HistoryItem.fromJson(Map<String, dynamic>.from(raw));
        }
      }
    } catch (_) {}
    return null;
  }

  @action
  Future<void> record({
    required int tmdbId,
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required int progressSeconds,
    int? durationSeconds,
    String? title,
    String? posterPath,
    String? backdropPath,
  }) async {
    try {
      await apiClient.post('/history', body: {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        'progressSeconds': progressSeconds,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (title != null) 'title': title,
        if (posterPath != null) 'posterPath': posterPath,
        if (backdropPath != null) 'backdropPath': backdropPath,
      });
    } catch (_) {
      // best-effort
    }
  }

  @action
  Future<void> remove(String id) async {
    try {
      await apiClient.delete('/history/$id');
      items.removeWhere((it) => it.id == id);
      continueWatching.removeWhere((it) => it.id == id);
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> clearAll() async {
    try {
      await apiClient.delete('/history');
      items.clear();
      continueWatching.clear();
    } catch (e) {
      errorMessage = e.toString();
    }
  }
}
