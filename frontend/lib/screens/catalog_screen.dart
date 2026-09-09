import 'package:flutter/material.dart';
import '../core/api_client.dart';
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
  late Future<List<Song>> songsFuture;

  bool get isEightD => widget.songType == '8d';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    final request = widget.api.songs(songType: widget.songType);
    setState(() => songsFuture = request);
  }

  Future<void> refreshAsync() async {
    refresh();
    await songsFuture;
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
      body: FutureBuilder<List<Song>>(
        future: songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
                child: Text('Unable to connect to Catws Songs.'));
          }
          final songs = snapshot.data ?? <Song>[];
          if (songs.isEmpty) {
            return Center(
                child: Text(isEightD
                    ? 'No public 8D songs yet.'
                    : 'No normal songs yet.'));
          }
          return RefreshIndicator(
            onRefresh: refreshAsync,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: songs.length + (isEightD ? 1 : 0),
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
                final songIndex = isEightD ? index - 1 : index;
                final song = songs[songIndex];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(song.coverUrl,
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
