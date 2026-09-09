class Song {
  final int id;
  final String title;
  final String artist;
  final String? album;
  final String category;
  final String? genre;
  final String? description;
  final String? mood;
  final String audioUrl;
  final String coverUrl;
  final double? duration;
  final double? durationSeconds;
  final String songType;
  final bool isFeatured;
  final bool isPublished;
  final DateTime? releaseAt;
  final bool isFavorite;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    required this.category,
    this.genre,
    this.description,
    this.mood,
    required this.audioUrl,
    required this.coverUrl,
    this.duration,
    this.durationSeconds,
    this.songType = 'normal',
    required this.isFeatured,
    this.isPublished = true,
    this.releaseAt,
    this.isFavorite = false,
  });

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: (j['id'] as num).toInt(),
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? 'Unknown Artist') as String,
        album: j['album'] as String?,
        category: (j['category'] ?? 'Other') as String,
        genre: j['genre'] as String?,
        description: j['description'] as String?,
        mood: j['mood'] as String?,
        audioUrl: (j['audio_url'] ?? '') as String,
        coverUrl: (j['cover_url'] ?? '') as String,
        duration: (j['duration'] as num?)?.toDouble(),
        durationSeconds: (j['duration_seconds'] as num?)?.toDouble() ??
            (j['duration'] as num?)?.toDouble(),
        songType: (j['song_type'] ?? 'normal') as String,
        isFeatured: j['is_featureured'] == true || j['is_featured'] == true,
        isPublished: j['is_published'] != false,
        releaseAt: j['release_at'] == null ? null : DateTime.tryParse(j['release_at'].toString()),
        isFavorite: j['is_favorite'] == true,
      );
}
