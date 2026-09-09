import 'song.dart';

class PlaylistSummary {
  final int id;
  final String name;
  final String description;
  final String? coverUrl;
  final int songCount;
  final DateTime createdAt;

  const PlaylistSummary({required this.id, required this.name, required this.description, this.coverUrl, required this.songCount, required this.createdAt});

  factory PlaylistSummary.fromJson(Map<String, dynamic> j) => PlaylistSummary(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        coverUrl: j['cover_url'] as String?,
        songCount: (j['song_count'] ?? 0) as int,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class PlaylistDetail extends PlaylistSummary {
  final List<Song> songs;

  const PlaylistDetail({
    required super.id,
    required super.name,
    required super.description,
    super.coverUrl,
    required super.songCount,
    required super.createdAt,
    required this.songs,
  });

  factory PlaylistDetail.fromJson(Map<String, dynamic> j) => PlaylistDetail(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        coverUrl: j['cover_url'] as String?,
        songCount: (j['song_count'] ?? 0) as int,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0),
        songs: ((j['songs'] ?? []) as List).map((e) => Song.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}
