import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// Local listener data. Normal listeners do not need an account for likes,
/// history, or playlists; only the small song metadata snapshots are stored.
class LocalPlaylist {
  final int id;
  final String name;
  final String description;
  final List<Song> songs;

  const LocalPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    this.songs = const [],
  });

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    final songs = (json['songs'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((value) => Song.fromJson(Map<String, dynamic>.from(value)))
        .toList();
    return LocalPlaylist(
      id: (json['id'] as num?)?.toInt() ??
          -DateTime.now().millisecondsSinceEpoch,
      name: (json['name'] ?? 'Playlist').toString(),
      description: (json['description'] ?? '').toString(),
      songs: songs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'songs': songs.map(_songToJson).toList(),
      };
}

Map<String, dynamic> _songToJson(Song song) => {
      'id': song.id,
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      'category': song.category,
      'genre': song.genre,
      'description': song.description,
      'mood': song.mood,
      'audio_url': song.audioUrl,
      'cover_url': song.coverUrl,
      'duration': song.duration,
      'duration_seconds': song.durationSeconds,
      'song_type': song.songType,
      'is_featured': song.isFeatured,
      'is_published': song.isPublished,
      'release_at': song.releaseAt?.toIso8601String(),
      'is_favorite': song.isFavorite,
    };

class LocalLibraryStore extends ChangeNotifier {
  static const _favoritesKey = 'catws.local.favorites';
  static const _historyKey = 'catws.local.history';
  static const _playlistsKey = 'catws.local.playlists';

  SharedPreferences? _prefs;
  final Map<int, Song> _favorites = {};
  final List<Song> _history = [];
  final List<LocalPlaylist> _playlists = [];

  bool get ready => _prefs != null;
  List<Song> get favoriteSongs => _favorites.values.toList(growable: false);
  List<Song> get historySongs => List.unmodifiable(_history);
  List<LocalPlaylist> get playlists => List.unmodifiable(_playlists);

  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    _favorites
      ..clear()
      ..addAll(_readSongs(_prefs!.getString(_favoritesKey)));
    _history
      ..clear()
      ..addAll(_readSongs(_prefs!.getString(_historyKey)).values);
    _playlists
      ..clear()
      ..addAll(_readPlaylists(_prefs!.getString(_playlistsKey)));
    notifyListeners();
  }

  bool isFavorite(int songId) => _favorites.containsKey(songId);

  Future<void> toggleFavorite(Song song) async {
    if (isFavorite(song.id)) {
      _favorites.remove(song.id);
    } else {
      _favorites[song.id] = song;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> addHistory(Song song) async {
    _history.removeWhere((item) => item.id == song.id);
    _history.insert(0, song);
    if (_history.length > 100) _history.removeRange(100, _history.length);
    await _persist();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _persist();
    notifyListeners();
  }

  Future<LocalPlaylist> createPlaylist(String name,
      {String description = ''}) async {
    final playlist = LocalPlaylist(
      id: -DateTime.now().microsecondsSinceEpoch,
      name: name.trim(),
      description: description.trim(),
    );
    _playlists.insert(0, playlist);
    await _persist();
    notifyListeners();
    return playlist;
  }

  Future<void> addToPlaylist(int playlistId, Song song) async {
    final index =
        _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index < 0) return;
    final playlist = _playlists[index];
    if (playlist.songs.any((item) => item.id == song.id)) return;
    _playlists[index] = LocalPlaylist(
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      songs: [...playlist.songs, song],
    );
    await _persist();
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int playlistId, int songId) async {
    final index =
        _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index < 0) return;
    final playlist = _playlists[index];
    _playlists[index] = LocalPlaylist(
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      songs: playlist.songs.where((song) => song.id != songId).toList(),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> deletePlaylist(int playlistId) async {
    _playlists.removeWhere((playlist) => playlist.id == playlistId);
    await _persist();
    notifyListeners();
  }

  Map<int, Song> _readSongs(String? encoded) {
    if (encoded == null || encoded.isEmpty) return {};
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      final songs = <int, Song>{};
      for (final value in decoded.whereType<Map>()) {
        final song = Song.fromJson(Map<String, dynamic>.from(value));
        songs[song.id] = song;
      }
      return songs;
    } catch (_) {
      return {};
    }
  }

  List<LocalPlaylist> _readPlaylists(String? encoded) {
    if (encoded == null || encoded.isEmpty) return [];
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((value) =>
              LocalPlaylist.fromJson(Map<String, dynamic>.from(value)))
          .where((playlist) => playlist.name.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(
        _favoritesKey, jsonEncode(_favorites.values.map(_songToJson).toList()));
    await prefs.setString(
        _historyKey, jsonEncode(_history.map(_songToJson).toList()));
    await prefs.setString(_playlistsKey,
        jsonEncode(_playlists.map((item) => item.toJson()).toList()));
  }
}
