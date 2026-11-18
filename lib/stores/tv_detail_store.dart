import 'package:cineby_tv/models/tv_detail_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/tmdb_client.dart';
import 'package:mobx/mobx.dart';

part 'tv_detail_store.g.dart';

class TvDetailStore = _TvDetailStore with _$TvDetailStore;

abstract class _TvDetailStore with Store {
  @observable
  TvDetail? tvDetail;

  @observable
  SeasonDetail? selectedSeason;

  @observable
  int? selectedSeasonNumber;

  @observable
  bool isLoading = false;

  @observable
  bool isSeasonLoading = false;

  @observable
  String? errorMessage;

  // Bumped for every season request so a slow response for a season the user
  // has already moved off can't overwrite the one they're actually on.
  int _seasonSeq = 0;

  @action
  Future<void> fetchTvDetail(int tvId) async {
    isLoading = true;
    errorMessage = null;
    tvDetail = null;
    selectedSeason = null;
    selectedSeasonNumber = null;
    try {
      final res = await tmdbDio.get('$tvDetailUrl/$tvId$tvDetailParams');
      if (res.statusCode == 200) {
        tvDetail = TvDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
        if (tvDetail!.seasons.isNotEmpty) {
          await fetchSeason(tvId, tvDetail!.seasons.first.seasonNumber);
        }
      } else {
        errorMessage = 'Failed to load show';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> fetchSeason(int tvId, int seasonNumber) async {
    if (selectedSeasonNumber == seasonNumber && selectedSeason != null) return;
    final seq = ++_seasonSeq;
    isSeasonLoading = true;
    selectedSeasonNumber = seasonNumber;
    try {
      final res = await tmdbDio.get(
        '$tvSeasonUrl/$tvId/season/$seasonNumber$tvSeasonParams',
      );
      if (seq != _seasonSeq) return;
      if (res.statusCode == 200) {
        selectedSeason = SeasonDetail.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      } else {
        // selectedSeasonNumber already moved to the new chip; leaving the old
        // payload in selectedSeason would show season N-1's episodes under
        // season N's chip. Clearing it surfaces the "Couldn't load" note.
        selectedSeason = null;
        errorMessage = 'Failed to load season $seasonNumber';
      }
    } catch (e) {
      if (seq != _seasonSeq) return;
      selectedSeason = null;
      errorMessage = e.toString();
    } finally {
      if (seq == _seasonSeq) isSeasonLoading = false;
    }
  }
}
