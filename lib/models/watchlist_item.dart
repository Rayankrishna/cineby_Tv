class WatchlistItem {
  final String id;
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'
  final String? title;
  final String? posterPath;
  final DateTime addedAt;

  const WatchlistItem({
    required this.id,
    required this.tmdbId,
    required this.mediaType,
    this.title,
    this.posterPath,
    required this.addedAt,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> j) => WatchlistItem(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        tmdbId: (j['tmdbId'] ?? j['tmdb_id'] ?? 0) as int,
        mediaType: (j['mediaType'] ?? j['media_type'] ?? 'movie') as String,
        title: j['title'] as String?,
        posterPath: (j['posterPath'] ?? j['poster_path']) as String?,
        addedAt: DateTime.tryParse(
              (j['addedAt'] ?? j['createdAt'] ?? '') as String,
            ) ??
            DateTime.now(),
      );
}
