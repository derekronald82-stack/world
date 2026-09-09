import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/api_client.dart';
import '../core/local_library_store.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../widgets/playlist_animations.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  final ApiClient api;
  final LocalLibraryStore localLibrary;
  final bool remoteLibraryEnabled;
  final int initialIndex;
  const LibraryScreen({
    super.key,
    required this.api,
    required this.localLibrary,
    this.remoteLibraryEnabled = false,
    this.initialIndex = 0,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  late Future<List<Song>> likedFuture;
  late Future<List<PlaylistSummary>> playlistsFuture;
  late Future<List<Song>> historyFuture;

  static const accent = Color(0xFF984D45);
  static const ink = Color(0xFF403634);
  static const bg = Color(0xFFFFFAF7);

  @override
  void initState() {
    super.initState();
    tabs = TabController(
        length: 3,
        vsync: this,
        initialIndex: widget.initialIndex.clamp(0, 2).toInt());
    refresh();
  }

  void refresh() {
    final likedRequest = widget.remoteLibraryEnabled
        ? widget.api.favorites()
        : Future.value(widget.localLibrary.favoriteSongs);
    final playlistsRequest = widget.remoteLibraryEnabled
        ? widget.api.playlists()
        : Future.value(widget.localLibrary.playlists
            .map((playlist) => PlaylistSummary(
                  id: playlist.id,
                  name: playlist.name,
                  description: playlist.description,
                  songCount: playlist.songs.length,
                  createdAt: DateTime.fromMicrosecondsSinceEpoch(-playlist.id),
                ))
            .toList());
    final historyRequest = widget.remoteLibraryEnabled
        ? widget.api.history()
        : Future.value(widget.localLibrary.historySongs);
    setState(() {
      likedFuture = likedRequest;
      playlistsFuture = playlistsRequest.then((items) {
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return items;
      });
      historyFuture = historyRequest;
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> createPlaylist() async {
    final name = await showAnimatedPlaylistNameDialog(
      context,
      title: 'New playlist',
    );
    if (name == null || name.isEmpty) return;
    if (widget.remoteLibraryEnabled) {
      await widget.api.createPlaylist(name);
    } else {
      await widget.localLibrary.createPlaylist(name);
    }
    refresh();
  }

  void playQueue(List<Song> songs, int index) {
    if (songs.isEmpty) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen(
                  api: widget.api,
                  queue: songs,
                  initialIndex: index,
                  localLibrary: widget.localLibrary,
                  remoteLibraryEnabled: widget.remoteLibraryEnabled,
                )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Your Library',
            style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: tabs,
          labelColor: accent,
          unselectedLabelColor: const Color(0xFF806D67),
          indicatorColor: accent,
          tabs: const [
            Tab(text: 'Liked Songs'),
            Tab(text: 'Playlists'),
            Tab(text: 'History')
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: tabs,
        builder: (_, __) => tabs.index == 1
            ? FloatingActionButton.extended(
                onPressed: createPlaylist,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Playlist'))
            : const SizedBox.shrink(),
      ),
      body: TabBarView(
        controller: tabs,
        children: [
          _songsFuture(likedFuture, 'No liked songs yet.'),
          _playlists(),
          _history(),
        ],
      ),
    );
  }

  Widget _songsFuture(Future<List<Song>> future, String empty) {
    return FutureBuilder<List<Song>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator(color: accent));
        if (snap.hasError) return _error(friendlyApiError(snap.error!));
        final songs = snap.data ?? [];
        if (songs.isEmpty) return _empty(empty, Icons.favorite_border_rounded);
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: songs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) =>
                _songTile(songs[i], () => playQueue(songs, i)),
          ),
        );
      },
    );
  }

  Widget _playlists() {
    return FutureBuilder<List<PlaylistSummary>>(
      future: playlistsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator(color: accent));
        if (snap.hasError) return _error(friendlyApiError(snap.error!));
        final items = snap.data ?? [];
        if (items.isEmpty)
          return _empty(
              'Create your first playlist.', Icons.queue_music_rounded);
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = items[i];
              final heroTag = 'playlist-cover-${p.id}';
              return PlaylistSongEntrance(
                index: i,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  scale: 1,
                  child: Card(
                    elevation: 0,
                    color: const Color(0xFFFFEEE9),
                    child: ListTile(
                      leading: PlaylistHeroCover(
                        tag: heroTag,
                        coverUrl: p.coverUrl,
                        size: 52,
                        borderRadius: BorderRadius.circular(12),
                        backgroundColor: const Color(0xFFFFDAD4),
                      ),
                      title: Text(p.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: ink)),
                      subtitle: Text(
                          '${p.songCount} songs${p.description.isEmpty ? '' : ' • ${p.description}'}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final route = PlaylistRoute<void>(
                          builder: (_) => widget.remoteLibraryEnabled
                              ? PlaylistDetailScreen(
                                  api: widget.api,
                                  playlistId: p.id,
                                  heroTag: heroTag,
                                )
                              : LocalPlaylistDetailScreen(
                                  localLibrary: widget.localLibrary,
                                  playlistId: p.id,
                                  heroTag: heroTag,
                                ),
                        );
                        await Navigator.push(context, route);
                        if (mounted) refresh();
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _history() {
    return FutureBuilder<List<Song>>(
      future: historyFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator(color: accent));
        if (snap.hasError) return _error(friendlyApiError(snap.error!));
        final songs = snap.data ?? [];
        if (songs.isEmpty)
          return _empty('Your recently played songs will appear here.',
              Icons.history_rounded);
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  if (widget.remoteLibraryEnabled) {
                    await widget.api.clearHistory();
                  } else {
                    await widget.localLibrary.clearHistory();
                  }
                  refresh();
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear history'),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: songs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) =>
                    _songTile(songs[i], () => playQueue(songs, i)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _songTile(Song s, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(s.coverUrl,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  width: 54,
                  height: 54,
                  color: const Color(0xFFFFDAD4),
                  child: const Icon(Icons.music_note_rounded))),
        ),
        title: Text(s.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
        subtitle: Text('${s.artist} • ${s.category}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.play_circle_outline_rounded, color: accent),
        onTap: onTap,
      );

  Widget _empty(String text, IconData icon) => Center(
          child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: const Color(0xFFC89E94)),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF806D67)))
        ]),
      ));

  Widget _error(String text) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center)));
}

class PlaylistDetailScreen extends StatefulWidget {
  final ApiClient api;
  final int playlistId;
  final String heroTag;

  const PlaylistDetailScreen(
      {super.key,
      required this.api,
      required this.playlistId,
      this.heroTag = 'playlist-cover-remote'});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class LocalPlaylistDetailScreen extends StatefulWidget {
  final LocalLibraryStore localLibrary;
  final int playlistId;
  final String heroTag;

  const LocalPlaylistDetailScreen(
      {super.key,
      required this.localLibrary,
      required this.playlistId,
      this.heroTag = 'playlist-cover-local'});

  @override
  State<LocalPlaylistDetailScreen> createState() =>
      _LocalPlaylistDetailScreenState();
}

class _LocalPlaylistDetailScreenState extends State<LocalPlaylistDetailScreen> {
  static const accent = Color(0xFF984D45);
  static const bg = Color(0xFFFFFAF7);

  LocalPlaylist? get playlist {
    for (final item in widget.localLibrary.playlists) {
      if (item.id == widget.playlistId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final current = playlist;
    final artwork = current != null && current.songs.isNotEmpty
        ? current.songs.first.coverUrl
        : '';
    final meta = current == null ? '0 songs' : '${current.songs.length} songs';

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: bg,
              expandedHeight: 330,
              collapsedHeight: 84,
              leading: const BackButton(color: Color(0xFF403634)),
              title: Text(current?.name ?? 'Playlist',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF403634))),
              actions: [
                if (current != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFF403634)),
                    onPressed: () async {
                      try {
                        await widget.localLibrary.deletePlaylist(current.id);
                        if (mounted) Navigator.pop(context);
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Unable to delete this playlist.')),
                          );
                        }
                      }
                    },
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: AnimatedPlaylistHeader(
                  tag: widget.heroTag,
                  title: current?.name ?? 'Playlist',
                  owner: 'Your library',
                  meta: meta,
                  coverUrl: artwork,
                  backgroundColor: bg,
                  accent: accent,
                  onPlay: current == null || current.songs.isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                api: ApiClient(),
                                queue: current.songs,
                                initialIndex: 0,
                                localLibrary: widget.localLibrary,
                              ),
                            ),
                          );
                        },
                  onShuffle: current == null || current.songs.isEmpty
                      ? null
                      : () {
                          if (current.songs.isEmpty) return;
                          final shuffled = [...current.songs]..shuffle();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                api: ApiClient(),
                                queue: shuffled,
                                initialIndex: 0,
                                localLibrary: widget.localLibrary,
                              ),
                            ),
                          );
                        },
                ),
              ),
            ),
            if (current == null || current.songs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No songs in this playlist yet.'),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final song = current.songs[index];
                  return PlaylistSongEntrance(
                    index: index,
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(song.coverUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 52,
                                height: 52,
                                color: const Color(0xFFFFDAD4),
                                child: const Icon(Icons.music_note_rounded))),
                      ),
                      title: Text(song.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(song.artist),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                    api: ApiClient(),
                                    queue: current.songs,
                                    initialIndex: index,
                                    localLibrary: widget.localLibrary,
                                  ))),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded,
                            color: accent),
                        onPressed: () async {
                          try {
                            await widget.localLibrary
                                .removeFromPlaylist(current.id, song.id);
                            if (mounted) setState(() {});
                          } catch (_) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Unable to remove this song.')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  );
                }, childCount: current.songs.length),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Future<PlaylistDetail> future;
  static const accent = Color(0xFF984D45);

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    final request = widget.api.playlist(widget.playlistId);
    setState(() {
      future = request;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlaylistDetail>(
      future: future,
      builder: (context, snap) {
        final p = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        final error = snap.hasError;
        final content = p ??
            PlaylistDetail(
              id: widget.playlistId,
              name: 'Playlist',
              description: '',
              songCount: 0,
              createdAt: DateTime.now(),
              songs: const [],
            );

        return Scaffold(
          backgroundColor: const Color(0xFFFFFAF7),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: const Color(0xFFFFFAF7),
                  expandedHeight: 330,
                  collapsedHeight: 84,
                  leading: const BackButton(color: Color(0xFF403634)),
                  title: Text(content.name,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF403634))),
                  actions: [
                    if (p != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Color(0xFF403634)),
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PlaylistEditorScreen(api: widget.api, playlist: p)));
                          if (changed == true && mounted) refresh();
                        },
                      ),
                    if (p != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFF403634)),
                        onPressed: () async {
                          try {
                            await widget.api.deletePlaylist(p.id);
                            if (mounted) Navigator.pop(context);
                          } catch (_) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Unable to delete this playlist.')),
                              );
                            }
                          }
                        },
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: loading || p == null
                        ? AnimatedPlaylistHeader(
                            tag: widget.heroTag,
                            title: content.name,
                            owner: 'Loading playlist…',
                            meta: 'Fetching songs',
                            coverUrl: '',
                            backgroundColor: const Color(0xFFFFFAF7),
                            accent: accent,
                          )
                        : AnimatedPlaylistHeader(
                            tag: widget.heroTag,
                            title: p.name,
                            owner: 'Catws Songs',
                            meta: '${p.songs.length} songs',
                            coverUrl: p.coverUrl?.isNotEmpty == true
                                ? p.coverUrl
                                : p.songs.isNotEmpty
                                ? p.songs.first.coverUrl
                                : '',
                            backgroundColor: const Color(0xFFFFFAF7),
                            accent: accent,
                            onPlay: p.songs.isEmpty
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlayerScreen(
                                          api: widget.api,
                                          queue: p.songs,
                                          initialIndex: 0,
                                        ),
                                      ),
                                    ),
                            onShuffle: p.songs.isEmpty
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlayerScreen(
                                          api: widget.api,
                                          queue: [...p.songs]..shuffle(),
                                          initialIndex: 0,
                                        ),
                                      ),
                                    ),
                          ),
                  ),
                ),
                if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: accent),
                    ),
                  )
                else if (error)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Unable to load this playlist.'),
                          TextButton(
                              onPressed: refresh, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                else if (p == null || p.songs.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No songs in this playlist yet.'),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final s = p.songs[i];
                      return PlaylistSongEntrance(
                        index: i,
                        child: ListTile(
                          leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(s.coverUrl,
                                  width: 52, height: 52, fit: BoxFit.cover)),
                          title: Text(s.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.artist),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PlayerScreen(
                                        api: widget.api,
                                        queue: p.songs,
                                        initialIndex: i,
                                      ))),
                          trailing: IconButton(
                            icon:
                                const Icon(Icons.remove_circle_outline_rounded),
                            onPressed: () async {
                              try {
                                await widget.api.removeFromPlaylist(p.id, s.id);
                                if (mounted) refresh();
                              } catch (_) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Unable to remove this song.')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      );
                    }, childCount: p.songs.length),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PlaylistEditorScreen extends StatefulWidget {
  final ApiClient api;
  final PlaylistDetail playlist;

  const PlaylistEditorScreen({super.key, required this.api, required this.playlist});

  @override
  State<PlaylistEditorScreen> createState() => _PlaylistEditorScreenState();
}

class _PlaylistEditorScreenState extends State<PlaylistEditorScreen> {
  late final TextEditingController name;
  late final TextEditingController description;
  PlatformFile? cover;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.playlist.name);
    description = TextEditingController(text: widget.playlist.description);
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result != null && mounted) setState(() => cover = result.files.single);
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Playlist name is required.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.updatePlaylist(
        widget.playlist.id,
        name: name.text.trim(),
        description: description.text.trim(),
        coverName: cover?.name,
        coverBytes: cover?.bytes,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendlyApiError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit playlist')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Playlist name')),
          const SizedBox(height: 12),
          TextField(controller: description, maxLength: 240, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: busy ? null : pickCover, icon: const Icon(Icons.image_outlined), label: Text(cover == null ? 'Choose playlist picture' : 'Change picture')),
          if (cover?.bytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(cover!.bytes!, height: 220, fit: BoxFit.cover)),
            TextButton.icon(onPressed: busy ? null : () => setState(() => cover = null), icon: const Icon(Icons.delete_outline_rounded), label: const Text('Remove picture')),
          ],
          if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : save, icon: const Icon(Icons.save_outlined), label: Text(busy ? 'Saving...' : 'Save playlist')),
        ],
      ),
    );
  }
}
