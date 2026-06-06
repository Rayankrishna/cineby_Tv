class HistoryItem {
  final String id;
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'
  final int? seasonNumber;
  final int? episodeNumber;
  final int progressSeconds;
  final int? durationSeconds;
  final bool completed;
  final String? title;
  final String? posterPath;
  final String? backdropPath;
  final DateTime watchedAt;
  final DateTime updatedAt;

  const HistoryItem({
    required this.id,
    required this.tmdbId,
    required this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
    required this.progressSeconds,
    this.durationSeconds,
    this.completed = false,
    this.title,
    this.posterPath,
    this.backdropPath,
    required this.watchedAt,
    required this.updatedAt,
  });

  double get progressFraction {
    final d = durationSeconds ?? 0;
    if (d <= 0) return 0;
    return (progressSeconds / d).clamp(0.0, 1.0);
  }

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        tmdbId: (j['tmdbId'] ?? j['tmdb_id'] ?? 0) as int,
        mediaType: (j['mediaType'] ?? j['media_type'] ?? 'movie') as String,
        seasonNumber: (j['seasonNumber'] ?? j['season_number']) as int?,
        episodeNumber: (j['episodeNumber'] ?? j['episode_number']) as int?,
        progressSeconds: (j['progressSeconds'] ?? j['progress_seconds'] ?? 0) as int,
        durationSeconds: (j['durationSeconds'] ?? j['duration_seconds']) as int?,
        completed: (j['completed'] ?? false) as bool,
        title: j['title'] as String?,
        posterPath: (j['posterPath'] ?? j['poster_path']) as String?,
        backdropPath: (j['backdropPath'] ?? j['backdrop_path']) as String?,
        watchedAt: DateTime.tryParse(
              (j['watchedAt'] ?? j['createdAt'] ?? '') as String,
            ) ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(
              (j['updatedAt'] ?? '') as String,
            ) ??
            DateTime.now(),
      );
}
