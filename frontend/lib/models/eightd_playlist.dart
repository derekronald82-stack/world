import 'user_8d_creation.dart';

class EightDPlaylistSummary {
  final int id;
  final String name;
  final String description;
  final int songCount;

  const EightDPlaylistSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.songCount,
  });

  factory EightDPlaylistSummary.fromJson(Map<String, dynamic> j) => EightDPlaylistSummary(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        songCount: (j['song_count'] ?? 0) as int,
      );
}

class EightDPlaylistDetail extends EightDPlaylistSummary {
  final List<User8DCreation> songs;

  const EightDPlaylistDetail({
    required super.id,
    required super.name,
    required super.description,
    required super.songCount,
    required this.songs,
  });

  factory EightDPlaylistDetail.fromJson(Map<String, dynamic> j) => EightDPlaylistDetail(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        songCount: (j['song_count'] ?? 0) as int,
        songs: ((j['songs'] ?? []) as List)
            .map((e) => User8DCreation.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
