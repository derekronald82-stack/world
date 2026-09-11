import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/catalog_store.dart';
import '../core/local_library_store.dart';
import '../models/song.dart';
import 'player_screen.dart';

class CatalogScreen extends StatefulWidget {
  final ApiClient api;
  final String songType;
  final LocalLibraryStore? localLibrary;
  final bool remoteLibraryEnabled;

  const CatalogScreen({
    super.key,
    required this.api,
    required this.songType,
    this.localLibrary,
    this.remoteLibraryEnabled = false,
  });

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<CatalogSnapshot> songsFuture;
  CatalogStatus catalogStatus = CatalogStatus.loading;
  final ScrollController scrollController = ScrollController();
  List<Song> loadedSongs = const [];
  int offset = 0;
  bool loadingMore = false;
  bool hasMore = true;

  bool get isEightD => widget.songType == '8d';

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    refresh();
  }

  @override
  void dispose() {
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void refresh() {
    offset = 0;
    hasMore = true;
    loadedSongs = const [];
    final request = widget.api.loadCatalog(
      songType: widget.songType,
      onStatus: (snapshot) {
        if (mounted) {
          setState(() {
            catalogStatus = snapshot.status;
            if (snapshot.songs.isNotEmpty) loadedSongs = snapshot.songs;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      songsFuture = request;
      catalogStatus = CatalogStatus.loading;
    });
    request.then((snapshot) {
      if (!mounted) return;
      setState(() {
        loadedSongs = snapshot.songs;
        offset = snapshot.songs.length;
        hasMore = snapshot.songs.length >= 60;
      });
    }, onError: (_) {});
  }

  Future<void> refreshAsync() async {
    refresh();
    await songsFuture;
  }

  void _onScroll() {
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || !hasMore || loadedSongs.isEmpty) return;
    setState(() => loadingMore = true);
    try {
      final page = await widget.api
          .songs(songType: widget.songType, limit: 60, offset: offset);
      if (!mounted) return;
      setState(() {
        loadedSongs = [...loadedSongs, ...page];
        offset += page.length;
        hasMore = page.length == 60;
      });
    } catch (_) {
      // Keep the existing page visible; a subsequent scroll can retry.
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> play(List<Song> songs, int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          api: widget.api,
          queue: songs,
          initialIndex: index,
          localLibrary: widget.localLibrary,
          remoteLibraryEnabled: widget.remoteLibraryEnabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = isEightD ? '8D Songs' : 'Normal Songs';
    return Scaffold(
      appBar: AppBar(
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
      body: FutureBuilder<CatalogSnapshot>(
        future: songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            if (catalogStatus == CatalogStatus.connecting) {
              return const Center(child: Text('Connecting to Catws Songs...'));
            }
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
                child: Text('Unable to connect to Catws Songs.'));
          }
          final catalog = snapshot.data;
          if (catalog != null &&
              catalog.isConnecting &&
              catalog.songs.isEmpty) {
            return const Center(child: Text('Connecting to Catws Songs...'));
          }
          final songs =
              loadedSongs.isNotEmpty ? loadedSongs : catalog?.songs ?? <Song>[];
          if (songs.isEmpty) {
            return Center(
                child: Text(isEightD
                    ? 'No public 8D songs yet.'
                    : 'No normal songs yet.'));
          }
          return RefreshIndicator(
            onRefresh: refreshAsync,
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: songs.length + (isEightD ? 1 : 0) + (hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (isEightD && index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text(
                        'Headphones recommended for the best 8D experience.',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  );
                }
                final contentIndex = isEightD ? index - 1 : index;
                if (contentIndex == songs.length) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final songIndex = contentIndex;
                final song = songs[songIndex];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(song.coverUrl,
                        cacheWidth: 160,
                        cacheHeight: 160,
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            width: 58,
                            height: 58,
                            child: Icon(Icons.music_note_rounded))),
                  ),
                  title: Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${song.artist}${isEightD ? '  |  8D' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      onPressed: () => play(songs, songIndex)),
                  onTap: () => play(songs, songIndex),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
