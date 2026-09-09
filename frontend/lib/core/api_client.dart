import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/playlist.dart';
import '../models/eightd_playlist.dart';
import '../models/song.dart';
import '../models/user_8d_creation.dart';
import 'catalog_store.dart';

String friendlyApiError(Object error) {
  final raw = error.toString();
  final lowered = raw.toLowerCase();
  if (error is TimeoutException ||
      error is http.ClientException ||
      lowered.contains('socketexception') ||
      lowered.contains('failed host lookup') ||
      lowered.contains('connection')) {
    return 'Catws Songs is waking up. Please wait a moment and try again.';
  }
  final message = raw.replaceFirst('Exception: ', '').trim();
  return message.isEmpty ? 'Something went wrong. Please try again.' : message;
}

class ApiClient {
  static const requestTimeout = Duration(seconds: 10);
  // Production build example:
  // flutter build apk --dart-define=API_BASE_URL=https://your-api-domain.com
  // A public HTTPS backend removes any same-Wi-Fi/laptop dependency.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  String? token;
  final CatalogStore catalogStore = CatalogStore();
  void Function()? onAuthenticationFailure;

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, String> get _authHeaders => {
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, String> get _requiredAuthHeaders {
    final value = token?.trim();
    if (value == null || value.isEmpty) {
      onAuthenticationFailure?.call();
      throw Exception('Session expired. Please login again.');
    }
    return {'Authorization': 'Bearer $value'};
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final r = await http.post(Uri.parse('$baseUrl/api/auth/login'),
        headers: _jsonHeaders,
        body: jsonEncode({'username': username, 'password': password}));
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<Map<String, dynamic>> register(
      String username, String password) async {
    final r = await http.post(Uri.parse('$baseUrl/api/auth/register'),
        headers: _jsonHeaders,
        body: jsonEncode({'username': username, 'password': password}));
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<List<Song>> songs(
      {String q = '', String category = '', String? songType}) async {
    final params = <String, String>{};
    if (q.trim().isNotEmpty) params['q'] = q.trim();
    if (category.trim().isNotEmpty) params['category'] = category.trim();
    if (songType != null) params['song_type'] = songType == 'eightd' ? '8d' : songType;
    final uri = Uri.parse('$baseUrl/api/songs')
        .replace(queryParameters: params.isEmpty ? null : params);
    final r = await http.get(uri).timeout(requestTimeout);
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<CatalogSnapshot> loadCatalog({String q = '', String category = '', String? songType}) {
    final isRootCatalog = q.trim().isEmpty && category.trim().isEmpty && songType == null;
    return catalogStore.load(
      () => songs(q: q, category: category, songType: songType),
      cacheResponse: isRootCatalog,
    );
  }

  Future<Map<String, dynamic>> health() async {
    final r = await http.get(Uri.parse('$baseUrl/api/health')).timeout(requestTimeout);
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<List<Song>> featuredSongs() async {
    final r = await http.get(Uri.parse('$baseUrl/api/songs/featured'));
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<Song>> latestSongs() async {
    final r = await http.get(Uri.parse('$baseUrl/api/songs/latest'));
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<String>> categories() async {
    final r = await http.get(Uri.parse('$baseUrl/api/songs/categories'));
    return (List<dynamic>.from(_decode(r)))
        .map((value) => value.toString())
        .toList();
  }

  Future<List<Song>> searchSongs(String query) async {
    final uri = Uri.parse('$baseUrl/api/search')
        .replace(queryParameters: {'q': query});
    final r = await http.get(uri);
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<Song>> adminSongs({String? songType}) async {
    final path =
        songType == null ? '/api/admin/songs' : '/api/admin/songs/$songType';
    final r = await http.get(Uri.parse('$baseUrl$path'),
        headers: _requiredAuthHeaders);
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> adminStats() async {
    final r = await http.get(Uri.parse('$baseUrl/api/admin/stats'), headers: _requiredAuthHeaders);
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<String> convert8d(int songId,
      {double panSpeed = .5,
      double intensity = 1.0,
      double reverb = .35}) async {
    final r = await http.post(Uri.parse('$baseUrl/api/audio/convert/$songId'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'pan_speed': panSpeed,
          'intensity': intensity,
          'reverb': reverb,
        }));
    return (Map<String, dynamic>.from(_decode(r)))['output_url'] as String;
  }

  Future<User8DCreation> createPersonal8d({
    required String title,
    required String audioName,
    required Uint8List audioBytes,
    double panSpeed = .5,
    double intensity = 1.0,
    double reverb = .35,
    double decay = 2.5,
  }) async {
    final req =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/audio/create'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields.addAll({
      'title': title,
      'pan_speed': panSpeed.toString(),
      'intensity': intensity.toString(),
      'reverb': reverb.toString(),
      'decay': decay.toString(),
    });
    req.files.add(
        http.MultipartFile.fromBytes('audio', audioBytes, filename: audioName));
    final streamed = await req.send();
    final response = await http.Response.fromStream(streamed);
    return User8DCreation.fromJson(
        Map<String, dynamic>.from(_decode(response)));
  }

  Future<List<User8DCreation>> my8dCreations({bool savedOnly = true}) async {
    final uri = Uri.parse('$baseUrl/api/audio/creations').replace(
      queryParameters: {'saved_only': savedOnly.toString()},
    );
    final r = await http.get(uri, headers: _authHeaders);
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => User8DCreation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<User8DCreation> save8dToCatws(int creationId) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/audio/creations/$creationId/save'),
      headers: _authHeaders,
    );
    return User8DCreation.fromJson(Map<String, dynamic>.from(_decode(r)));
  }

  Future<void> delete8dCreation(int creationId) async {
    final r = await http.delete(
      Uri.parse('$baseUrl/api/audio/creations/$creationId'),
      headers: _authHeaders,
    );
    if (r.statusCode != 204) _decode(r);
  }

  Future<String> get8dDownloadLink(int creationId) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/audio/creations/$creationId/download-link'),
      headers: _authHeaders,
    );
    return Map<String, dynamic>.from(_decode(r))['url'] as String;
  }

  Future<void> addSong({
    required String title,
    required String artist,
    String album = '',
    required String category,
    String genre = '',
    required String songType,
    required bool featured,
    bool published = true,
    DateTime? releaseAt,
    required String audioName,
    required Uint8List audioBytes,
    required String coverName,
    required Uint8List coverBytes,
  }) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/api/admin/songs/$songType'));
    req.headers.addAll(_requiredAuthHeaders);
    req.fields.addAll({
      'title': title,
      'artist': artist,
      if (album.trim().isNotEmpty) 'album': album.trim(),
      'category': category,
      if (genre.trim().isNotEmpty) 'genre': genre.trim(),
      'song_type': songType,
      'is_featured': featured.toString(),
      'is_published': published.toString(),
      if (releaseAt != null) 'release_at': releaseAt.toUtc().toIso8601String(),
    });
    req.files.add(
        http.MultipartFile.fromBytes('audio', audioBytes, filename: audioName));
    req.files.add(
        http.MultipartFile.fromBytes('cover', coverBytes, filename: coverName));
    final streamed = await req.send();
    final response = await http.Response.fromStream(streamed);
    _decode(response);
  }

  Future<void> updateSong({
    required int id,
    required String title,
    required String artist,
    String? album,
    required String category,
    String? genre,
    required bool featured,
    bool? published,
    required DateTime? releaseAt,
    String? audioName,
    Uint8List? audioBytes,
    String? coverName,
    Uint8List? coverBytes,
  }) async {
    final req = http.MultipartRequest(
        'PATCH', Uri.parse('$baseUrl/api/admin/songs/$id'));
    req.headers.addAll(_requiredAuthHeaders);
    req.fields.addAll({
      'title': title,
      'artist': artist,
      if (album != null) 'album': album,
      'category': category,
      if (genre != null) 'genre': genre,
      'is_featured': featured.toString(),
      'release_action': releaseAt == null ? 'clear' : 'set',
      if (published != null) 'is_published': published.toString(),
      if (releaseAt != null) 'release_at': releaseAt.toUtc().toIso8601String(),
    });
    if (audioBytes != null && audioName != null) {
      req.files.add(http.MultipartFile.fromBytes('audio', audioBytes,
          filename: audioName));
    }
    if (coverBytes != null && coverName != null) {
      req.files.add(http.MultipartFile.fromBytes('cover', coverBytes,
          filename: coverName));
    }
    final streamed = await req.send();
    final response = await http.Response.fromStream(streamed);
    _decode(response);
  }

  Future<void> deleteSong(int id) async {
    final r = await http.delete(Uri.parse('$baseUrl/api/admin/songs/$id'),
        headers: _requiredAuthHeaders);
    if (r.statusCode != 204) _decode(r);
  }

  Future<List<Song>> favorites() async {
    final r = await http.get(Uri.parse('$baseUrl/api/library/favorites'),
        headers: _authHeaders);
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> setFavorite(int songId, bool value) async {
    final uri = Uri.parse('$baseUrl/api/library/favorites/$songId');
    final r = value
        ? await http.post(uri, headers: _authHeaders)
        : await http.delete(uri, headers: _authHeaders);
    if (value || r.statusCode != 204) _decode(r);
  }

  Future<void> recordPlay(int songId) async {
    final r = await http.post(Uri.parse('$baseUrl/api/library/history/$songId'),
        headers: _authHeaders);
    _decode(r);
  }

  Future<List<Song>> history() async {
    final r = await http.get(Uri.parse('$baseUrl/api/library/history'),
        headers: _authHeaders);
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> clearHistory() async {
    final r = await http.delete(Uri.parse('$baseUrl/api/library/history'),
        headers: _authHeaders);
    if (r.statusCode != 204) _decode(r);
  }

  Future<List<PlaylistSummary>> playlists() async {
    final r = await http.get(Uri.parse('$baseUrl/api/library/playlists'),
        headers: _authHeaders);
    final data = _decode(r) as List<dynamic>;
    return data
        .map((e) => PlaylistSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PlaylistSummary> createPlaylist(String name,
      {String description = ''}) async {
    final r = await http.post(Uri.parse('$baseUrl/api/library/playlists'),
        headers: _jsonHeaders,
        body: jsonEncode({'name': name, 'description': description}));
    return PlaylistSummary.fromJson(Map<String, dynamic>.from(_decode(r)));
  }

  Future<PlaylistSummary> updatePlaylist(
    int id, {
    String? name,
    String? description,
    String? coverName,
    Uint8List? coverBytes,
  }) async {
    final req = http.MultipartRequest('PATCH', Uri.parse('$baseUrl/api/library/playlists/$id'));
    req.headers.addAll(_requiredAuthHeaders);
    if (name != null) req.fields['name'] = name;
    if (description != null) req.fields['description'] = description;
    if (coverName != null && coverBytes != null) {
      req.files.add(http.MultipartFile.fromBytes('cover', coverBytes, filename: coverName));
    }
    final streamed = await req.send();
    final response = await http.Response.fromStream(streamed);
    return PlaylistSummary.fromJson(Map<String, dynamic>.from(_decode(response)));
  }

  Future<PlaylistDetail> playlist(int id) async {
    final r = await http.get(Uri.parse('$baseUrl/api/library/playlists/$id'),
        headers: _authHeaders);
    return PlaylistDetail.fromJson(Map<String, dynamic>.from(_decode(r)));
  }

  Future<void> addToPlaylist(int playlistId, int songId) async {
    final r = await http.post(
        Uri.parse('$baseUrl/api/library/playlists/$playlistId/songs/$songId'),
        headers: _authHeaders);
    _decode(r);
  }

  Future<void> removeFromPlaylist(int playlistId, int songId) async {
    final r = await http.delete(
        Uri.parse('$baseUrl/api/library/playlists/$playlistId/songs/$songId'),
        headers: _authHeaders);
    if (r.statusCode != 204) _decode(r);
  }

  Future<void> deletePlaylist(int playlistId) async {
    final r = await http.delete(
        Uri.parse('$baseUrl/api/library/playlists/$playlistId'),
        headers: _authHeaders);
    if (r.statusCode != 204) _decode(r);
  }

  Future<List<EightDPlaylistSummary>> eightdPlaylists() async {
    final r = await http.get(Uri.parse('$baseUrl/api/library/8d-playlists'),
        headers: _authHeaders);
    final data = _decode(r) as List<dynamic>;
    return data
        .map(
            (e) => EightDPlaylistSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<EightDPlaylistSummary> createEightDPlaylist(String name,
      {String description = ''}) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/library/8d-playlists'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'description': description}),
    );
    return EightDPlaylistSummary.fromJson(
        Map<String, dynamic>.from(_decode(r)));
  }

  Future<EightDPlaylistDetail> eightdPlaylist(int id) async {
    final r = await http.get(Uri.parse('$baseUrl/api/library/8d-playlists/$id'),
        headers: _authHeaders);
    return EightDPlaylistDetail.fromJson(Map<String, dynamic>.from(_decode(r)));
  }

  Future<void> addToEightDPlaylist(int playlistId, int creationId) async {
    final r = await http.post(
      Uri.parse(
          '$baseUrl/api/library/8d-playlists/$playlistId/songs/$creationId'),
      headers: _authHeaders,
    );
    _decode(r);
  }

  Future<void> removeFromEightDPlaylist(int playlistId, int creationId) async {
    final r = await http.delete(
      Uri.parse(
          '$baseUrl/api/library/8d-playlists/$playlistId/songs/$creationId'),
      headers: _authHeaders,
    );
    if (r.statusCode != 204) _decode(r);
  }

  Future<void> deleteEightDPlaylist(int playlistId) async {
    final r = await http.delete(
        Uri.parse('$baseUrl/api/library/8d-playlists/$playlistId'),
        headers: _authHeaders);
    if (r.statusCode != 204) _decode(r);
  }

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      body = r.body;
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final sessionExpired = r.statusCode == 401 && token != null;
      if (sessionExpired) {
        onAuthenticationFailure?.call();
      }
      final detail = body is Map ? body['detail'] : body;
      throw Exception(sessionExpired
          ? 'Session expired. Please login again.'
          : detail ?? 'Request failed (${r.statusCode})');
    }
    return body;
  }
}
