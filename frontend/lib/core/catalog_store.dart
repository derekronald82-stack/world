import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

enum CatalogStatus { loading, connecting, success, cachedData, realEmpty, offline, error }

class CatalogSnapshot {
  final CatalogStatus status;
  final List<Song> songs;

  const CatalogSnapshot(this.status, this.songs);

  bool get isConnecting => status == CatalogStatus.connecting || status == CatalogStatus.offline || status == CatalogStatus.error;
}

/// Last-successful-response cache for Render cold starts.
/// A failed request never overwrites a known-good catalog.
class CatalogStore {
  static const _cacheKey = 'catws.catalog.last_success.v1';

  Future<CatalogSnapshot> load(
    Future<List<Song>> Function() request, {
    bool allowRetry = true,
    bool cacheResponse = true,
  }) async {
    Object? lastError;
    final delays = allowRetry
        ? const [Duration.zero, Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8), Duration(seconds: 12)]
        : const [Duration.zero];
    for (final delay in delays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      try {
        final songs = await request();
        if (cacheResponse) await _save(songs);
        return CatalogSnapshot(
          songs.isEmpty ? CatalogStatus.realEmpty : CatalogStatus.success,
          songs,
        );
      } catch (error) {
        lastError = error;
      }
    }

    final cached = await _read();
    if (cached.isNotEmpty) return CatalogSnapshot(CatalogStatus.cachedData, cached);
    return CatalogSnapshot(
      lastError == null ? CatalogStatus.offline : CatalogStatus.error,
      const [],
    );
  }

  Future<void> _save(List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(songs.map(_toJson).toList()));
  }

  Future<List<Song>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((value) => Song.fromJson(Map<String, dynamic>.from(value)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _toJson(Song song) => {
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'category': song.category,
        'mood': song.mood,
        'audio_url': song.audioUrl,
        'cover_url': song.coverUrl,
        'duration': song.duration,
        'duration_seconds': song.duration,
        'song_type': song.songType,
        'is_featured': song.isFeatured,
        'is_published': song.isPublished,
        'release_at': song.releaseAt?.toIso8601String(),
        'is_favorite': song.isFavorite,
      };
}
