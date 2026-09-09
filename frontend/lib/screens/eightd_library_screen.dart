import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../models/eightd_playlist.dart';
import '../models/user_8d_creation.dart';
import '../widgets/playlist_animations.dart';

class EightDLibraryScreen extends StatefulWidget {
  final ApiClient api;
  const EightDLibraryScreen({super.key, required this.api});

  @override
  State<EightDLibraryScreen> createState() => _EightDLibraryScreenState();
}

class _EightDLibraryScreenState extends State<EightDLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  late Future<List<User8DCreation>> songsFuture;
  late Future<List<EightDPlaylistSummary>> playlistsFuture;
  final player = AudioPlayer();
  int? playingId;

  static const accent = Color(0xFF704B7A);
  static const ink = Color(0xFF403634);
  static const bg = Color(0xFFFFFAF7);

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 2, vsync: this);
    refresh();
  }

  void refresh() {
    final songsRequest = widget.api.my8dCreations(savedOnly: true);
    final playlistsRequest = widget.api.eightdPlaylists();
    setState(() {
      songsFuture = songsRequest;
      playlistsFuture = playlistsRequest;
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> _play(User8DCreation item) async {
    try {
      if (playingId == item.id && player.playing) {
        await player.pause();
      } else {
        await player.setUrl(item.outputUrl);
        await player.play();
        playingId = item.id;
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not play this 8D song.')));
    }
  }

  Future<void> _download(User8DCreation item) async {
    try {
      final link = await widget.api.get8dDownloadLink(item.id);
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    }
  }

  Future<EightDPlaylistSummary?> _createPlaylistDialog() async {
    final name = await showAnimatedPlaylistNameDialog(
      context,
      title: 'New 8D playlist',
    );
    if (name == null || name.isEmpty) return null;
    final p = await widget.api.createEightDPlaylist(name);
    refresh();
    return p;
  }

  Future<void> _addToPlaylist(User8DCreation item) async {
    List<EightDPlaylistSummary> lists;
    try {
      lists = await widget.api.eightdPlaylists();
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                  title: Text('Add to 8D playlist',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900))),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
                title: const Text('Create new 8D playlist',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final p = await _createPlaylistDialog();
                  if (p != null) {
                    await widget.api.addToEightDPlaylist(p.id, item.id);
                    refresh();
                  }
                },
              ),
              ...lists.map((p) => ListTile(
                    leading: const Icon(Icons.spatial_audio_rounded),
                    title: Text(p.name),
                    subtitle: Text('${p.songCount} 8D songs'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await widget.api.addToEightDPlaylist(p.id, item.id);
                      refresh();
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added to ${p.name}.')));
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
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('8D Songs Library',
            style: TextStyle(fontWeight: FontWeight.w900)),
        bottom: TabBar(
          controller: tabs,
          labelColor: accent,
          indicatorColor: accent,
          tabs: const [Tab(text: 'My 8D Songs'), Tab(text: '8D Playlists')],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: tabs,
        builder: (_, __) => tabs.index == 1
            ? FloatingActionButton.extended(
                onPressed: _createPlaylistDialog,
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('8D Playlist'),
              )
            : const SizedBox.shrink(),
      ),
      body: TabBarView(controller: tabs, children: [_songs(), _playlists()]),
    );
  }

  Widget _songs() {
    return FutureBuilder<List<User8DCreation>>(
      future: songsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snap.hasError)
          return const Center(child: Text('Unable to connect to Catws Songs.'));
        final items = snap.data ?? [];
        if (items.isEmpty)
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                      'No saved 8D songs yet. Create an 8D song and tap “Save to Catws”.',
                      textAlign: TextAlign.center)));
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final item = items[i];
              final active = playingId == item.id && player.playing;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE9DDF0),
                  child: Icon(
                      active
                          ? Icons.pause_rounded
                          : Icons.spatial_audio_rounded,
                      color: accent),
                ),
                title: Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: ink)),
                subtitle: Text(item.sourceFilename,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _play(item),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'playlist') _addToPlaylist(item);
                    if (v == 'download') _download(item);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'playlist',
                        child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.playlist_add_rounded),
                            title: Text('Add to 8D playlist'))),
                    PopupMenuItem(
                        value: 'download',
                        child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.download_rounded),
                            title: Text('Download'))),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _playlists() {
    return FutureBuilder<List<EightDPlaylistSummary>>(
      future: playlistsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snap.hasError)
          return const Center(child: Text('Unable to connect to Catws Songs.'));
        final items = snap.data ?? [];
        if (items.isEmpty)
          return const Center(child: Text('Create your first 8D playlist.'));
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = items[i];
              final heroTag = 'playlist-cover-8d-${p.id}';
              return PlaylistSongEntrance(
                index: i,
                child: Card(
                  elevation: 0,
                  color: const Color(0xFFF4EAF8),
                  child: ListTile(
                    leading: PlaylistHeroCover(
                      tag: heroTag,
                      coverUrl: '',
                      size: 52,
                      borderRadius: BorderRadius.circular(12),
                      backgroundColor: const Color(0xFFE4D1EC),
                      icon: Icons.spatial_audio_rounded,
                    ),
                    title: Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, color: ink)),
                    subtitle: Text(
                        '${p.songCount} 8D songs${p.description.isEmpty ? '' : ' • ${p.description}'}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        PlaylistRoute<void>(
                          builder: (_) => EightDPlaylistDetailScreen(
                            api: widget.api,
                            playlistId: p.id,
                            heroTag: heroTag,
                          ),
                        ),
                      );
                      if (mounted) refresh();
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class EightDPlaylistDetailScreen extends StatefulWidget {
  final ApiClient api;
  final int playlistId;
  final String heroTag;

  const EightDPlaylistDetailScreen({
    super.key,
    required this.api,
    required this.playlistId,
    this.heroTag = 'playlist-cover-8d',
  });

  @override
  State<EightDPlaylistDetailScreen> createState() =>
      _EightDPlaylistDetailScreenState();
}

class _EightDPlaylistDetailScreenState
    extends State<EightDPlaylistDetailScreen> {
  late Future<EightDPlaylistDetail> future;
  final player = AudioPlayer();
  int? playingId;

  static const accent = Color(0xFF704B7A);
  static const ink = Color(0xFF403634);
  static const bg = Color(0xFFFFFAF7);

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    final request = widget.api.eightdPlaylist(widget.playlistId);
    setState(() {
      future = request;
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _play(User8DCreation item) async {
    try {
      if (playingId == item.id && player.playing) {
        await player.pause();
      } else {
        await player.setUrl(item.outputUrl);
        await player.play();
        playingId = item.id;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Song unavailable.')),
        );
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EightDPlaylistDetail>(
      future: future,
      builder: (context, snap) {
        final p = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        final content = p ??
            EightDPlaylistDetail(
              id: widget.playlistId,
              name: '8D Playlist',
              description: '',
              songCount: 0,
              songs: const [],
            );
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
                  leading: const BackButton(color: ink),
                  title: Text(content.name,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ink)),
                  actions: [
                    if (p != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: ink),
                        onPressed: () async {
                          try {
                            await widget.api.deleteEightDPlaylist(p.id);
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
                    background: AnimatedPlaylistHeader(
                      tag: widget.heroTag,
                      title: content.name,
                      owner: 'Your 8D library',
                      meta: '${content.songCount} 8D songs',
                      backgroundColor: bg,
                      accent: accent,
                      icon: Icons.spatial_audio_rounded,
                      onPlay: p == null || p.songs.isEmpty
                          ? null
                          : () => _play(p.songs.first),
                      onShuffle: p == null || p.songs.isEmpty
                          ? null
                          : () {
                              final shuffled = [...p.songs]..shuffle();
                              _play(shuffled.first);
                            },
                    ),
                  ),
                ),
                if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snap.hasError)
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
                        child: Text('No 8D songs in this playlist yet.')),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final item = p.songs[i];
                        final active = playingId == item.id && player.playing;
                        return PlaylistSongEntrance(
                          index: i,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFE4D1EC),
                              child: Icon(
                                active
                                    ? Icons.pause_rounded
                                    : Icons.spatial_audio_rounded,
                                color: accent,
                              ),
                            ),
                            title: Text(item.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(item.sourceFilename,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _play(item),
                            trailing: IconButton(
                              icon: const Icon(
                                  Icons.remove_circle_outline_rounded),
                              onPressed: () async {
                                try {
                                  await widget.api
                                      .removeFromEightDPlaylist(p.id, item.id);
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
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
