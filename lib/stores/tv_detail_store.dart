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
    isSeasonLoading = true;
    selectedSeasonNumber = seasonNumber;
    try {
      final res = await tmdbDio.get(
        '$tvSeasonUrl/$tvId/season/$seasonNumber$tvSeasonParams',
      );
      if (res.statusCode == 200) {
        selectedSeason = SeasonDetail.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSeasonLoading = false;
    }
  }
}
