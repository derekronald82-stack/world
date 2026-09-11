import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

/// One process-wide catalog player. Screens subscribe to it, but navigation
/// never disposes or recreates the audio controller.
class PlayerService extends ChangeNotifier {
  PlayerService._() {
    _indexSubscription = player.currentIndexStream.listen((value) {
      if (value == null || value < 0 || value >= queue.length || value == _index) {
        return;
      }
      _index = value;
      notifyListeners();
    });
  }

  static final PlayerService instance = PlayerService._();

  final AudioPlayer player = AudioPlayer();
  StreamSubscription<int?>? _indexSubscription;
  ConcatenatingAudioSource? _queueSource;
  String? _queueKey;
  List<Song> queue = const [];
  int _index = 0;

  int get index => _index;

  set index(int value) {
    if (queue.isEmpty) {
      _index = 0;
    } else {
      _index = value.clamp(0, queue.length - 1).toInt();
    }
    notifyListeners();
  }

  Song? get currentSong => queue.isEmpty ? null : queue[_index];

  void setQueue(List<Song> songs, {int startIndex = 0}) {
    final key = _fingerprint(songs);
    final sameQueue = key == _queueKey;
    queue = List.unmodifiable(songs);
    _index = queue.isEmpty ? 0 : startIndex.clamp(0, queue.length - 1).toInt();
    _queueKey = key;
    if (!sameQueue) _queueSource = null;
    notifyListeners();
  }

  Future<void> loadQueue({bool autoPlay = true}) async {
    if (queue.isEmpty) return;

    if (_queueSource != null && _queueKey == _fingerprint(queue)) {
      if (player.currentIndex != _index) {
        await player.seek(Duration.zero, index: _index);
      }
      if (autoPlay) await player.play();
      return;
    }

    final source = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: queue
          .map((song) => AudioSource.uri(
                Uri.parse(song.audioUrl),
                tag: song.id,
              ))
          .toList(growable: false),
    );
    _queueSource = source;
    await player.setAudioSource(
      source,
      initialIndex: _index,
      preload: true,
    );
    if (autoPlay) await player.play();
  }

  Future<void> seekToIndex(int value, {bool autoPlay = true}) async {
    if (queue.isEmpty) return;
    index = value;
    if (_queueSource == null) {
      await loadQueue(autoPlay: autoPlay);
      return;
    }
    await player.seek(Duration.zero, index: _index);
    if (autoPlay) await player.play();
  }

  /// Plays a one-off preview (for example a generated 8D file) without
  /// destroying the metadata queue used by the Home mini-player.
  Future<void> playStandalone(String url, {bool autoPlay = true}) async {
    _queueSource = null;
    await player.setLoopMode(LoopMode.off);
    await player.setUrl(url);
    if (autoPlay) await player.play();
  }

  String _fingerprint(Iterable<Song> songs) =>
      songs.map((song) => '${song.id}:${song.audioUrl}').join('|');

  Future<void> disposeAtAppShutdown() async {
    await _indexSubscription?.cancel();
    await player.dispose();
  }
}
