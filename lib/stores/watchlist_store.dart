import 'package:cineby_tv/models/watchlist_item.dart';
import 'package:cineby_tv/services/api_client.dart';
import 'package:mobx/mobx.dart';

part 'watchlist_store.g.dart';

class WatchlistStore = _WatchlistStore with _$WatchlistStore;

abstract class _WatchlistStore with Store {
  @observable
  ObservableList<WatchlistItem> items = ObservableList<WatchlistItem>();

  @observable
  ObservableMap<String, bool> containsCache = ObservableMap<String, bool>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  String _key(int tmdbId, String mediaType) => '$tmdbId:$mediaType';

  @action
  Future<void> fetch() async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await apiClient.get('/watchlist');
      if (res.statusCode == 200 && res.data is Map) {
        final list = (res.data['items'] as List? ?? []);
        items = ObservableList.of(list
            .map((e) => WatchlistItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
        containsCache.clear();
        for (final it in items) {
          containsCache[_key(it.tmdbId, it.mediaType)] = true;
        }
      } else {
        errorMessage = 'Failed to load watchlist';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> checkContains(int tmdbId, String mediaType) async {
    final k = _key(tmdbId, mediaType);
    if (containsCache.containsKey(k)) return containsCache[k]!;
    try {
      final res = await apiClient.get(
        '/watchlist/contains/$tmdbId',
        query: {'mediaType': mediaType},
      );
      final inWl = res.statusCode == 200 &&
          res.data is Map &&
          (res.data['inWatchlist'] == true);
      containsCache[k] = inWl;
      return inWl;
    } catch (_) {
      return false;
    }
  }

  @action
  Future<void> add({
    required int tmdbId,
    required String mediaType,
    String? title,
    String? posterPath,
  }) async {
    try {
      await apiClient.post('/watchlist', body: {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        if (title != null) 'title': title,
        if (posterPath != null) 'posterPath': posterPath,
      });
      containsCache[_key(tmdbId, mediaType)] = true;
      await fetch();
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> remove({required int tmdbId, required String mediaType}) async {
    try {
      await apiClient.delete('/watchlist/$tmdbId', query: {'mediaType': mediaType});
      containsCache[_key(tmdbId, mediaType)] = false;
      items.removeWhere((it) => it.tmdbId == tmdbId && it.mediaType == mediaType);
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> toggle({
    required int tmdbId,
    required String mediaType,
    String? title,
    String? posterPath,
  }) async {
    final exists = await checkContains(tmdbId, mediaType);
    if (exists) {
      await remove(tmdbId: tmdbId, mediaType: mediaType);
    } else {
      await add(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        posterPath: posterPath,
      );
    }
  }
}
