import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

/// One process-wide catalog player. Screens subscribe to it, but navigation
/// never disposes or recreates the audio controller.
class PlayerService {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  final AudioPlayer player = AudioPlayer();
  List<Song> queue = const [];
  int index = 0;

  Song? get currentSong => queue.isEmpty ? null : queue[index.clamp(0, queue.length - 1).toInt()];

  void setQueue(List<Song> songs, {int startIndex = 0}) {
    queue = List.unmodifiable(songs);
    index = queue.isEmpty ? 0 : startIndex.clamp(0, queue.length - 1);
  }

  Future<void> disposeAtAppShutdown() => player.dispose();
}
