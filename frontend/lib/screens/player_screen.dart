import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../core/api_client.dart';
import '../core/local_library_store.dart';
import '../core/player_service.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../widgets/playlist_animations.dart';

class PlayerScreen extends StatefulWidget {
  final ApiClient api;
  final List<Song> queue;
  final int initialIndex;
  final LocalLibraryStore? localLibrary;
  final bool remoteLibraryEnabled;

  const PlayerScreen({
    super.key,
    required this.api,
    required this.queue,
    this.initialIndex = 0,
    this.localLibrary,
    this.remoteLibraryEnabled = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final player = PlayerService.instance.player;
  final playerService = PlayerService.instance;
  late int index;
  double pan = .5, intensity = 1.0, reverb = .35;
  bool converting = false;
  bool favorite = false;
  bool shuffle = false;
  bool repeatOne = false;
  String? convertedUrl;
  String? error;
  bool skipping = false;
  Timer? sleepTimer;
  int? sleepMinutes;
  StreamSubscription<PlayerState>? stateSub;
  StreamSubscription<int?>? indexSub;

  static const accent = Color(0xFF984D45);
  static const ink = Color(0xFF403634);
  static const bg = Color(0xFFFFFAF7);

  Song get song => widget.queue[index];

  @override
  void initState() {
    super.initState();
    index = widget.queue.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.queue.length - 1).toInt();
    playerService.setQueue(widget.queue, startIndex: index);
    // Repeat-one is screen state; never leak it into a newly opened playlist.
    player.setLoopMode(LoopMode.off);
    if (widget.queue.isEmpty) return;
    _loadCurrent(autoPlay: true);
    _loadFavorite();
    indexSub = player.currentIndexStream.listen(_onPlayerIndexChanged);
    stateSub = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (repeatOne) {
          player.seek(Duration.zero);
          player.play();
        }
      }
    });
  }

  @override
  void dispose() {
    sleepTimer?.cancel();
    stateSub?.cancel();
    indexSub?.cancel();
    // The catalog player is process-wide and must continue across routes.
    super.dispose();
  }

  Future<void> _loadCurrent({required bool autoPlay}) async {
    convertedUrl = null;
    error = null;
    try {
      await playerService.loadQueue(autoPlay: autoPlay);
      if (widget.remoteLibraryEnabled) {
        widget.api.recordPlay(song.id).catchError((_) {});
      } else {
        widget.localLibrary?.addHistory(song).catchError((_) {});
      }
      if (autoPlay) await player.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load this track.');
    }
  }

  void _onPlayerIndexChanged(int? nextIndex) {
    if (!mounted || nextIndex == null || nextIndex < 0 || nextIndex >= widget.queue.length) {
      return;
    }
    if (nextIndex == index) return;
    setState(() {
      index = nextIndex;
      convertedUrl = null;
      favorite = false;
    });
    if (widget.remoteLibraryEnabled) {
      widget.api.recordPlay(song.id).catchError((_) {});
    } else {
      widget.localLibrary?.addHistory(song).catchError((_) {});
    }
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    if (!widget.remoteLibraryEnabled) {
      if (mounted)
        setState(
            () => favorite = widget.localLibrary?.isFavorite(song.id) ?? false);
      return;
    }
    try {
      final liked = await widget.api.favorites();
      if (mounted) setState(() => favorite = liked.any((s) => s.id == song.id));
    } catch (_) {}
  }

  Future<void> toggleFavorite() async {
    final newValue = !favorite;
    setState(() => favorite = newValue);
    try {
      if (widget.remoteLibraryEnabled) {
        await widget.api.setFavorite(song.id, newValue);
      } else {
        await widget.localLibrary?.toggleFavorite(song);
      }
    } catch (_) {
      if (mounted) setState(() => favorite = !newValue);
    }
  }

  Future<void> next({bool autoPlay = true}) async {
    if (widget.queue.isEmpty || skipping) return;
    skipping = true;
    try {
      if (shuffle && widget.queue.length > 1) {
        var nextIndex = Random().nextInt(widget.queue.length);
        if (nextIndex == index) {
          nextIndex = (nextIndex + 1) % widget.queue.length;
        }
        index = nextIndex;
      } else {
        index = (index + 1) % widget.queue.length;
      }
      playerService.index = index;
      favorite = false;
      await playerService.seekToIndex(index, autoPlay: autoPlay);
      _loadFavorite();
    } finally {
      skipping = false;
    }
  }

  Future<void> previous() async {
    if (widget.queue.isEmpty || skipping) return;
    if ((player.position.inSeconds) > 4) {
      await player.seek(Duration.zero);
      return;
    }
    skipping = true;
    index = (index - 1 + widget.queue.length) % widget.queue.length;
    playerService.index = index;
    favorite = false;
    try {
      await playerService.seekToIndex(index, autoPlay: true);
      _loadFavorite();
    } finally {
      skipping = false;
    }
  }

  Future<void> convert() async {
    setState(() {
      converting = true;
      error = null;
    });
    try {
      final url = await widget.api.convert8d(song.id,
          panSpeed: pan, intensity: intensity, reverb: reverb);
      convertedUrl = url;
      await playerService.playStandalone(url);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = friendlyApiError(e));
    } finally {
      if (mounted) setState(() => converting = false);
    }
  }

  Future<void> originalVersion() async {
    convertedUrl = null;
    playerService.setQueue(widget.queue, startIndex: index);
    await playerService.loadQueue(autoPlay: true);
    if (mounted) setState(() {});
  }

  void setSleepTimer(int? minutes) {
    sleepTimer?.cancel();
    sleepMinutes = minutes;
    if (minutes != null) {
      sleepTimer = Timer(Duration(minutes: minutes), () async {
        await player.pause();
        if (mounted) {
          setState(() => sleepMinutes = null);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Sleep timer ended. Music paused.')));
        }
      });
    }
    setState(() {});
  }

  void sleepTimerSheet() {
    const values = [5, 10, 15, 30, 45, 60];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                  title: Text('Sleep timer',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800))),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...values.map((m) => ChoiceChip(
                        selected: sleepMinutes == m,
                        label: Text('$m min'),
                        onSelected: (_) {
                          Navigator.pop(context);
                          setSleepTimer(m);
                        },
                      )),
                  ActionChip(
                    avatar: const Icon(Icons.timer_off_outlined, size: 18),
                    label: const Text('Off'),
                    onPressed: () {
                      Navigator.pop(context);
                      setSleepTimer(null);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> addToPlaylistSheet() async {
    if (!widget.remoteLibraryEnabled) {
      await _addToLocalPlaylistSheet();
      return;
    }
    List<PlaylistSummary> lists;
    try {
      lists = await widget.api.playlists();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Add to playlist',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                trailing: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    final c = TextEditingController();
                    final name = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('New playlist'),
                        content: TextField(
                            controller: c,
                            autofocus: true,
                            decoration: const InputDecoration(
                                hintText: 'Playlist name')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () =>
                                  Navigator.pop(context, c.text.trim()),
                              child: const Text('Create')),
                        ],
                      ),
                    );
                    c.dispose();
                    if (name != null && name.isNotEmpty) {
                      final p = await widget.api.createPlaylist(name);
                      await widget.api.addToPlaylist(p.id, song.id);
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added to ${p.name}')));
                    }
                  },
                ),
              ),
              if (lists.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No playlists yet. Tap + to create one.')),
              ...lists.take(8).map((p) => ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.queue_music_rounded)),
                    title: Text(p.name),
                    subtitle: Text('${p.songCount} songs'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await widget.api.addToPlaylist(p.id, song.id);
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added to ${p.name}')));
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToLocalPlaylistSheet() async {
    final local = widget.localLibrary;
    if (local == null) return;
    final lists = local.playlists;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Add to local playlist',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                trailing: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    final c = TextEditingController();
                    final name = await showDialog<String>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('New playlist'),
                        content: TextField(
                            controller: c,
                            autofocus: true,
                            maxLength: 80,
                            decoration: const InputDecoration(
                                hintText: 'Playlist name')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, c.text.trim()),
                              child: const Text('Create')),
                        ],
                      ),
                    );
                    c.dispose();
                    if (name == null || name.isEmpty) return;
                    final playlist = await local.createPlaylist(name);
                    await local.addToPlaylist(playlist.id, song);
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to ${playlist.name}')));
                  },
                ),
              ),
              if (lists.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No playlists yet. Tap + to create one.')),
              ...lists.take(8).map((playlist) => ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.queue_music_rounded)),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.songs.length} songs'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await local.addToPlaylist(playlist.id, song);
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Added to ${playlist.name}')));
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.queue.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('Now Playing')),
        body: const Center(child: Text('No songs in this queue.')),
      );
    }
    final artworkSize = min(300.0, MediaQuery.sizeOf(context).width - 44);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(convertedUrl == null ? 'Now Playing' : '8D Version'),
        actions: [
          IconButton(
              onPressed: sleepTimerSheet,
              icon: Icon(sleepMinutes == null
                  ? Icons.timer_outlined
                  : Icons.timer_rounded)),
          IconButton(
              onPressed: addToPlaylistSheet,
              icon: const Icon(Icons.playlist_add_rounded)),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAudioBackdrop(
              playbackStream: player.playerStateStream
                  .map((state) => state.playing)
                  .distinct(),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
            children: [
              Center(
                child: Hero(
                  tag: 'song-${song.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.network(
                      song.coverUrl,
                      width: artworkSize,
                      height: artworkSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: artworkSize,
                          height: artworkSize,
                          color: const Color(0xFFFFDAD4),
                          child: Icon(Icons.music_note_rounded,
                              size: artworkSize * .3)),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 25,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            color: ink)),
                    const SizedBox(height: 5),
                    Text('${song.artist} • ${song.category}',
                        style: const TextStyle(
                            color: Color(0xFF806D67), fontSize: 15.5)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                  onPressed: toggleFavorite,
                  icon: Icon(
                      favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: favorite ? accent : ink)),
            ],
          ),
          const SizedBox(height: 8),
          _progress(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  onPressed: () => setState(() => shuffle = !shuffle),
                  icon: Icon(Icons.shuffle_rounded,
                      color: shuffle ? accent : ink)),
              IconButton(
                  onPressed: previous,
                  iconSize: 40,
                  icon: const Icon(Icons.skip_previous_rounded)),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (_, snap) {
                  final playing = snap.data?.playing ?? false;
                  return IconButton.filled(
                    style: IconButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(66, 66)),
                    onPressed: () => playing ? player.pause() : player.play(),
                    iconSize: 38,
                    icon: Icon(playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                  );
                },
              ),
              IconButton(
                  onPressed: next,
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next_rounded)),
              IconButton(
                  onPressed: () {
                    final enabled = !repeatOne;
                    setState(() => repeatOne = enabled);
                    player.setLoopMode(
                        enabled ? LoopMode.one : LoopMode.off);
                  },
                  icon: Icon(Icons.repeat_one_rounded,
                      color: repeatOne ? accent : ink)),
            ],
          ),
          if (sleepMinutes != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                  child: Chip(
                      avatar: const Icon(Icons.bedtime_outlined, size: 18),
                      label: Text('Sleep timer: $sleepMinutes min'))),
            ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: const Color(0xFFFFEEE9),
            child: ExpansionTile(
              leading: const Icon(Icons.surround_sound_rounded, color: accent),
              title: const Text('8D Studio',
                  style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
              subtitle: Text(convertedUrl == null
                  ? 'Pan + reverb controls'
                  : '8D version is active'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              children: [
                _slider(
                    'Pan speed', pan, .1, 1.5, (v) => setState(() => pan = v)),
                _slider('8D intensity', intensity, 0, 1.5,
                    (v) => setState(() => intensity = v)),
                _slider('Reverb', reverb, .30, .40,
                    (v) => setState(() => reverb = v)),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(error!,
                          style: const TextStyle(color: Colors.red))),
                Row(
                  children: [
                    if (convertedUrl != null)
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: originalVersion,
                              icon: const Icon(Icons.music_note_rounded),
                              label: const Text('Original'))),
                    if (convertedUrl != null) const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: converting ? null : convert,
                        style: FilledButton.styleFrom(
                            backgroundColor: ink,
                            minimumSize: const Size.fromHeight(50)),
                        icon: converting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.surround_sound_rounded),
                        label: Text(converting ? 'Converting...' : 'Create 8D'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: const Color(0xFFFFF3EF),
            child: ListTile(
              leading: const Icon(Icons.queue_music_rounded, color: accent),
              title: const Text('Up next',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(widget.queue.length <= 1
                  ? 'No other tracks in this queue'
                  : '${widget.queue.length - 1} more tracks'),
              trailing: widget.queue.length <= 1
                  ? null
                  : Text(widget.queue[(index + 1) % widget.queue.length].title,
                      overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
        ],
      ),
    );
  }

  Widget _progress() {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, posSnap) {
            var position = posSnap.data ?? Duration.zero;
            if (position > duration && duration > Duration.zero)
              position = duration;
            final maxValue = max(1, duration.inMilliseconds).toDouble();
            final value =
                position.inMilliseconds.clamp(0, maxValue.toInt()).toDouble();
            return Column(
              children: [
                Slider(
                  value: value,
                  max: maxValue,
                  onChanged: duration == Duration.zero
                      ? null
                      : (v) => player.seek(Duration(milliseconds: v.round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(_fmt(position)), Text(_fmt(duration))]),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _slider(String label, double value, double minV, double maxV,
          ValueChanged<double> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Text('$label  ${value.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Slider(value: value, min: minV, max: maxV, onChanged: onChanged),
      ]);
}
