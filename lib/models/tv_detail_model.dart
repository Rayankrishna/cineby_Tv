class Genre {
  final int id;
  final String name;
  const Genre({required this.id, required this.name});
  factory Genre.fromJson(Map<String, dynamic> j) =>
      Genre(id: (j['id'] ?? 0) as int, name: (j['name'] ?? '') as String);
}

class CastMember {
  final String name;
  final String? character;
  final String? profilePath;
  const CastMember({required this.name, this.character, this.profilePath});
  factory CastMember.fromJson(Map<String, dynamic> j) => CastMember(
        name: (j['name'] ?? '') as String,
        character: j['character'] as String?,
        profilePath: j['profile_path'] as String?,
      );
}

class SeasonSummary {
  final int id;
  final int seasonNumber;
  final String? name;
  final int? episodeCount;
  final String? posterPath;
  final String? airDate;
  const SeasonSummary({
    required this.id,
    required this.seasonNumber,
    this.name,
    this.episodeCount,
    this.posterPath,
    this.airDate,
  });
  factory SeasonSummary.fromJson(Map<String, dynamic> j) => SeasonSummary(
        id: (j['id'] ?? 0) as int,
        seasonNumber: (j['season_number'] ?? 0) as int,
        name: j['name'] as String?,
        episodeCount: j['episode_count'] as int?,
        posterPath: j['poster_path'] as String?,
        airDate: j['air_date'] as String?,
      );
}

class Episode {
  final int seasonNumber;
  final int episodeNumber;
  final String? name;
  final String? overview;
  final String? airDate;
  final String? stillPath;
  final int? runtime;
  const Episode({
    required this.seasonNumber,
    required this.episodeNumber,
    this.name,
    this.overview,
    this.airDate,
    this.stillPath,
    this.runtime,
  });
  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        seasonNumber: (j['season_number'] ?? 0) as int,
        episodeNumber: (j['episode_number'] ?? 0) as int,
        name: j['name'] as String?,
        overview: j['overview'] as String?,
        airDate: j['air_date'] as String?,
        stillPath: j['still_path'] as String?,
        runtime: j['runtime'] as int?,
      );
}

class SeasonDetail {
  final int seasonNumber;
  final List<Episode> episodes;
  const SeasonDetail({required this.seasonNumber, required this.episodes});
  factory SeasonDetail.fromJson(Map<String, dynamic> j) => SeasonDetail(
        seasonNumber: (j['season_number'] ?? 0) as int,
        episodes: ((j['episodes'] ?? []) as List)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TvDetail {
  final int id;
  final String? name;
  final String? overview;
  final String? tagline;
  final String? posterPath;
  final String? backdropPath;
  final String? firstAirDate;
  final String? status;
  final double? voteAverage;
  final int? voteCount;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final List<Genre> genres;
  final List<CastMember> cast;
  final String? creatorName;
  final List<SeasonSummary> seasons;

  const TvDetail({
    required this.id,
    this.name,
    this.overview,
    this.tagline,
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.status,
    this.voteAverage,
    this.voteCount,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.genres = const [],
    this.cast = const [],
    this.creatorName,
    this.seasons = const [],
  });

  factory TvDetail.fromJson(Map<String, dynamic> j) {
    final credits = j['credits'] as Map<String, dynamic>?;
    final castJson = (credits?['cast'] ?? []) as List;
    final createdBy = (j['created_by'] ?? []) as List;
    final seasonsRaw = (j['seasons'] ?? []) as List;
    return TvDetail(
      id: (j['id'] ?? 0) as int,
      name: j['name'] as String?,
      overview: j['overview'] as String?,
      tagline: j['tagline'] as String?,
      posterPath: j['poster_path'] as String?,
      backdropPath: j['backdrop_path'] as String?,
      firstAirDate: j['first_air_date'] as String?,
      status: j['status'] as String?,
      voteAverage: (j['vote_average'] is num) ? (j['vote_average'] as num).toDouble() : null,
      voteCount: j['vote_count'] as int?,
      numberOfSeasons: j['number_of_seasons'] as int?,
      numberOfEpisodes: j['number_of_episodes'] as int?,
      genres: ((j['genres'] ?? []) as List)
          .map((e) => Genre.fromJson(e as Map<String, dynamic>))
          .toList(),
      cast: castJson
          .take(20)
          .map((e) => CastMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      creatorName: createdBy.isNotEmpty ? (createdBy.first['name'] as String?) : null,
      seasons: seasonsRaw
          .map((e) => SeasonSummary.fromJson(e as Map<String, dynamic>))
          .where((s) => s.seasonNumber > 0)
          .toList(),
    );
  }
}
