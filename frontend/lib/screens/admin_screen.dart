import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../models/song.dart';

class AdminScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onChanged;
  const AdminScreen({super.key, required this.api, required this.onChanged});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final title = TextEditingController();
  final artist = TextEditingController();
  final album = TextEditingController();
  final category = TextEditingController(text: 'Other');
  final genre = TextEditingController();
  PlatformFile? audio;
  PlatformFile? cover;
  bool featured = false;
  bool published = true;
  bool busy = false;
  String? message;
  String uploadStatus = 'Preparing...';
  DateTime? releaseAt;
  late Future<List<Song>> songsFuture;

  static const accent = Color(0xFF984D45);

  @override
  void initState() {
    super.initState();
    refreshSongs();
  }

  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    album.dispose();
    category.dispose();
    genre.dispose();
    super.dispose();
  }

  void refreshSongs() {
    final request = widget.api.adminSongs();
    setState(() {
      songsFuture = request;
    });
  }

  Future<void> pickAudio() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'],
      withData: true,
    );
    if (r != null) setState(() => audio = r.files.single);
  }

  Future<void> pickCover() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (r != null) setState(() => cover = r.files.single);
  }

  Future<void> pickReleaseTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: releaseAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: releaseAt == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(releaseAt!),
    );
    if (time == null) return;
    setState(() => releaseAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> upload(String songType) async {
    if (title.text.trim().isEmpty ||
        audio?.bytes == null ||
        cover?.bytes == null) {
      setState(
          () => message = 'Title, music file and cover image are required.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
      uploadStatus = 'Preparing...';
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => uploadStatus = 'Uploading audio...');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => uploadStatus = 'Uploading cover...');
      await widget.api.addSong(
        title: title.text.trim(),
        artist:
            artist.text.trim().isEmpty ? 'Unknown Artist' : artist.text.trim(),
        album: album.text.trim(),
        category: category.text.trim().isEmpty ? 'Other' : category.text.trim(),
        genre: genre.text.trim(),
        songType: songType,
        featured: featured,
        published: published,
        releaseAt: releaseAt,
        audioName: audio!.name,
        audioBytes: audio!.bytes!,
        coverName: cover!.name,
        coverBytes: cover!.bytes!,
      );
      title.clear();
      artist.clear();
      album.clear();
      genre.clear();
      setState(() {
        audio = null;
        cover = null;
        featured = false;
        published = true;
        releaseAt = null;
        uploadStatus = 'Complete';
        message = 'Song uploaded successfully.';
      });
      widget.onChanged();
      refreshSongs();
    } catch (e) {
      if (mounted) setState(() => message = friendlyApiError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String fmt(DateTime dt) {
    final local = dt.toLocal();
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} ${local.hour}:$m';
  }

  Future<void> editSong(Song song) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => _EditSongPage(api: widget.api, song: song)),
    );
    if (changed == true && mounted) {
      widget.onChanged();
      refreshSongs();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Song updated.')));
    }
  }

  Future<void> deleteSong(Song song) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete song?'),
        content: Text(
            'Delete “${song.title}”, its cover, audio and generated 8D files?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteSong(song.id);
      widget.onChanged();
      refreshSongs();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Song deleted.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin • Catws Music'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Dashboard'),
            Tab(text: 'Add Normal'),
            Tab(text: 'Add 8D'),
            Tab(text: 'Manage Normal'),
            Tab(text: 'Manage 8D')
          ]),
        ),
        body: TabBarView(children: [
          _dashboardTab(),
          _uploadTab('normal'),
          _uploadTab('8d'),
          _manageTab('normal'),
          _manageTab('8d')
        ]),
      ),
    );
  }

  Widget _dashboardTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.api.adminStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: accent));
        }
        if (snapshot.hasError) {
          return Center(child: Text(friendlyApiError(snapshot.error!)));
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final cards = <(String, String, IconData)>[
          ('Songs', '${data['songs'] ?? 0}', Icons.music_note_rounded),
          ('Users', '${data['users'] ?? 0}', Icons.people_outline_rounded),
          ('Playlists', '${data['playlists'] ?? 0}', Icons.queue_music_rounded),
          ('Likes', '${data['favorites'] ?? 0}', Icons.favorite_border_rounded),
          ('8D jobs', '${data['conversions'] ?? 0}', Icons.spatial_audio_rounded),
        ];
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Admin Dashboard', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('CATWS SONGS catalog health and content overview.'),
              const SizedBox(height: 20),
              ...cards.map((card) => Card(
                    elevation: 0,
                    color: const Color(0xFFFFEEE9),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.white, child: Icon(card.$3, color: accent)),
                      title: Text(card.$1),
                      trailing: Text(card.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _uploadTab(String songType) {
    final isEightD = songType == '8d';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(isEightD ? 'Add 8D Song' : 'Add Normal Song',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        const SizedBox(height: 6),
        Text(
            isEightD
                ? 'Public 8D catalog • saved separately from normal music.'
                : 'Normal catalog • available in the Normal Songs section.',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Song title')),
        const SizedBox(height: 12),
        TextField(
            controller: artist,
            decoration: const InputDecoration(labelText: 'Artist')),
        const SizedBox(height: 12),
        TextField(
            controller: album,
            decoration: const InputDecoration(labelText: 'Album (optional)')),
        const SizedBox(height: 12),
        TextField(
            controller: category,
            decoration: const InputDecoration(labelText: 'Category / mood')),
        const SizedBox(height: 14),
        TextField(
            controller: genre,
            decoration: const InputDecoration(labelText: 'Genre (optional)')),
        const SizedBox(height: 14),
        OutlinedButton.icon(
            onPressed: pickAudio,
            icon: const Icon(Icons.audio_file_rounded),
            label: Text(audio?.name ?? 'Choose music file')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: pickCover,
            icon: const Icon(Icons.image_outlined),
            label: Text(cover == null ? 'Choose cover image' : 'Change picture')),
        if (cover?.bytes != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(cover!.bytes!, height: 180, fit: BoxFit.cover),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : () => setState(() => cover = null),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove picture'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: const Color(0xFFFFEEE9),
          child: ListTile(
            leading: const Icon(Icons.schedule_rounded, color: accent),
            title: Text(releaseAt == null
                ? 'Publish immediately'
                : 'Scheduled: ${fmt(releaseAt!)}'),
            subtitle: const Text('Optional future release date and time'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (releaseAt != null)
                  IconButton(
                      onPressed: () => setState(() => releaseAt = null),
                      icon: const Icon(Icons.close_rounded)),
                IconButton(
                    onPressed: pickReleaseTime,
                    icon: const Icon(Icons.edit_calendar_rounded)),
              ],
            ),
          ),
        ),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: featured,
            onChanged: busy ? null : (v) => setState(() => featured = v),
            title: const Text('Featured song')),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: published,
            onChanged: busy ? null : (v) => setState(() => published = v),
            title: const Text('Published to users')),
        if (message != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(message!)),
        if (busy)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(uploadStatus,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: accent))),
        FilledButton.icon(
          onPressed: busy ? null : () => upload(songType),
          style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              minimumSize: const Size.fromHeight(54)),
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(busy
              ? 'Uploading...'
              : isEightD
                  ? 'Add 8D Song'
                  : 'Add Normal Song'),
        ),
      ],
    );
  }

  Widget _manageTab(String songType) {
    return FutureBuilder<List<Song>>(
      future: songsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator(color: accent));
        if (snap.hasError)
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(friendlyApiError(snap.error!))));
        final songs = (snap.data ?? [])
            .where((song) => song.songType == songType)
            .toList();
        if (songs.isEmpty)
          return const Center(child: Text('No songs uploaded yet.'));
        return RefreshIndicator(
          onRefresh: () async => refreshSongs(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
            itemCount: songs.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      '${songs.length} song${songs.length == 1 ? '' : 's'} • tap edit to change details, cover, audio or release time.',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                );
              }
              final s = songs[i - 1];
              final future =
                  s.releaseAt != null && s.releaseAt!.isAfter(DateTime.now());
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    s.coverUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 52,
                        height: 52,
                        color: const Color(0xFFFFDAD4),
                        child: const Icon(Icons.music_note_rounded)),
                  ),
                ),
                title:
                    Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(future
                    ? '${s.artist} • Scheduled ${fmt(s.releaseAt!)}'
                    : '${s.artist} • ${s.category}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => editSong(s)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Delete',
                        onPressed: () => deleteSong(s)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EditSongPage extends StatefulWidget {
  final ApiClient api;
  final Song song;
  const _EditSongPage({required this.api, required this.song});

  @override
  State<_EditSongPage> createState() => _EditSongPageState();
}

class _EditSongPageState extends State<_EditSongPage> {
  late final TextEditingController title;
  late final TextEditingController artist;
  late final TextEditingController album;
  late final TextEditingController category;
  late final TextEditingController genre;
  late bool featured;
  late bool published;
  DateTime? releaseAt;
  PlatformFile? audio;
  PlatformFile? cover;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.song.title);
    artist = TextEditingController(text: widget.song.artist);
    album = TextEditingController(text: widget.song.album ?? '');
    category = TextEditingController(text: widget.song.category);
    genre = TextEditingController(text: widget.song.genre ?? '');
    featured = widget.song.isFeatured;
    published = widget.song.isPublished;
    releaseAt = widget.song.releaseAt?.toLocal();
  }

  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    album.dispose();
    category.dispose();
    genre.dispose();
    super.dispose();
  }

  String fmt(DateTime dt) {
    final local = dt.toLocal();
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} ${local.hour}:$m';
  }

  Future<void> pickAudio() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'],
        withData: true);
    if (r != null) setState(() => audio = r.files.single);
  }

  Future<void> pickCover() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true);
    if (r != null) setState(() => cover = r.files.single);
  }

  Future<void> pickReleaseTime() async {
    final now = DateTime.now();
    final initial = releaseAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;
    setState(() => releaseAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      setState(() => error = 'Song title is required.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.updateSong(
        id: widget.song.id,
        title: title.text.trim(),
        artist:
            artist.text.trim().isEmpty ? 'Unknown Artist' : artist.text.trim(),
        album: album.text.trim(),
        category: category.text.trim().isEmpty ? 'Other' : category.text.trim(),
        genre: genre.text.trim(),
        featured: featured,
        published: published,
        releaseAt: releaseAt,
        audioName: audio?.name,
        audioBytes: audio?.bytes,
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
      appBar: AppBar(title: const Text('Edit song')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Song title')),
          const SizedBox(height: 12),
          TextField(
              controller: artist,
              decoration: const InputDecoration(labelText: 'Artist')),
          const SizedBox(height: 12),
          TextField(
              controller: album,
              decoration: const InputDecoration(labelText: 'Album (optional)')),
          const SizedBox(height: 12),
          TextField(
              controller: category,
              decoration: const InputDecoration(labelText: 'Category / mood')),
          const SizedBox(height: 14),
          TextField(
              controller: genre,
              decoration: const InputDecoration(labelText: 'Genre (optional)')),
          const SizedBox(height: 14),
          OutlinedButton.icon(
              onPressed: busy ? null : pickAudio,
              icon: const Icon(Icons.audio_file_rounded),
              label: Text(audio?.name ?? 'Keep current audio')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: busy ? null : pickCover,
              icon: const Icon(Icons.image_outlined),
              label: Text(cover?.name ?? 'Keep current cover')),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: Text(releaseAt == null
                  ? 'Publish immediately'
                  : 'Scheduled: ${fmt(releaseAt!)}'),
              subtitle: const Text('Change or clear the release schedule'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (releaseAt != null)
                    IconButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => releaseAt = null),
                        icon: const Icon(Icons.close_rounded)),
                  IconButton(
                      onPressed: busy ? null : pickReleaseTime,
                      icon: const Icon(Icons.edit_calendar_rounded)),
                ],
              ),
            ),
          ),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: featured,
              onChanged: busy ? null : (v) => setState(() => featured = v),
              title: const Text('Featured song')),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: published,
              onChanged: busy ? null : (v) => setState(() => published = v),
              title: const Text('Published to users')),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(error!, style: const TextStyle(color: Colors.red))),
          FilledButton.icon(
            onPressed: busy ? null : save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            icon: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(busy ? 'Saving...' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}
