import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../models/user_8d_creation.dart';

class Create8DScreen extends StatefulWidget {
  final ApiClient api;
  const Create8DScreen({super.key, required this.api});

  @override
  State<Create8DScreen> createState() => _Create8DScreenState();
}

class _Create8DScreenState extends State<Create8DScreen> {
  final title = TextEditingController();
  final player = AudioPlayer();
  PlatformFile? picked;
  Uint8List? audioBytes;
  User8DCreation? result;
  List<User8DCreation> saved = [];
  bool loading = false;
  bool loadingLibrary = true;
  String? error;
  int? playingId;
  double panSpeed = .5;
  double intensity = 1.0;
  double reverb = .35;
  double decay = 2.5;

  static const bg = Color(0xFFFFFAF7);
  static const ink = Color(0xFF403634);
  static const accent = Color(0xFF984D45);
  static const soft = Color(0xFFFFE6E1);

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    title.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    setState(() => loadingLibrary = true);
    try {
      saved = await widget.api.my8dCreations(savedOnly: true);
    } catch (_) {
      saved = [];
    }
    if (mounted) setState(() => loadingLibrary = false);
  }

  Future<void> _pickAudio() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'],
      withData: true,
      allowMultiple: false,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    if (f.bytes == null) {
      setState(() =>
          error = 'Could not read this audio file. Please choose it again.');
      return;
    }
    setState(() {
      picked = f;
      audioBytes = f.bytes;
      error = null;
      result = null;
      if (title.text.trim().isEmpty) {
        final dot = f.name.lastIndexOf('.');
        title.text = dot > 0 ? f.name.substring(0, dot) : f.name;
      }
    });
  }

  Future<void> _create() async {
    if (audioBytes == null || picked == null) {
      setState(() => error = 'Choose an audio file first.');
      return;
    }
    if (title.text.trim().isEmpty) {
      setState(() => error = 'Enter a name for your 8D song.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final created = await widget.api.createPersonal8d(
        title: title.text.trim(),
        audioName: picked!.name,
        audioBytes: audioBytes!,
        panSpeed: panSpeed,
        intensity: intensity,
        reverb: reverb,
        decay: decay,
      );
      if (mounted) setState(() => result = created);
    } catch (e) {
      if (mounted) setState(() => error = friendlyApiError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _preview(User8DCreation item) async {
    try {
      if (playingId == item.id && player.playing) {
        await player.pause();
        if (mounted) setState(() {});
        return;
      }
      await player.setUrl(item.outputUrl);
      await player.play();
      if (mounted) setState(() => playingId = item.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not preview this 8D song.')));
      }
    }
  }

  Future<void> _download(User8DCreation item) async {
    try {
      final link = await widget.api.get8dDownloadLink(item.id);
      final ok = await launchUrl(Uri.parse(link),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the download.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    }
  }

  Future<void> _saveToCatws(User8DCreation item) async {
    try {
      final updated = await widget.api.save8dToCatws(item.id);
      if (mounted) {
        setState(() => result = updated);
        await _loadLibrary();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Saved to My 8D Songs.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    }
  }

  Future<void> _addTo8dPlaylist(User8DCreation item) async {
    if (!item.savedToCatws) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save this 8D song to Catws first.')),
        );
      }
      return;
    }
    final lists = await widget.api.eightdPlaylists();
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
                          fontWeight: FontWeight.w900, fontSize: 20))),
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Create new 8D playlist'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final c = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('New 8D playlist'),
                      content: TextField(
                          controller: c,
                          autofocus: true,
                          decoration:
                              const InputDecoration(hintText: 'Playlist name')),
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
                  if (name == null || name.isEmpty) return;
                  final p = await widget.api.createEightDPlaylist(name);
                  await widget.api.addToEightDPlaylist(p.id, item.id);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to ${p.name}.')));
                },
              ),
              ...lists.map((p) => ListTile(
                    leading: const Icon(Icons.spatial_audio_rounded),
                    title: Text(p.name),
                    subtitle: Text('${p.songCount} 8D songs'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await widget.api.addToEightDPlaylist(p.id, item.id);
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

  Future<void> _delete(User8DCreation item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete 8D song?'),
        content:
            Text('“${item.title}” will be removed from your Catws storage.'),
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
    if (yes != true) return;
    await player.stop();
    await widget.api.delete8dCreation(item.id);
    if (result?.id == item.id && mounted) setState(() => result = null);
    await _loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Create your 8D song',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6E3E72), Color(0xFFB9686B)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.spatial_audio_off_rounded,
                    color: Colors.white, size: 38),
                SizedBox(height: 12),
                Text('Catws 8D Creator',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(
                    'Choose your audio, create an 8D version, then download it or save it to your Catws account.',
                    style: TextStyle(color: Colors.white, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
              controller: title,
              decoration: const InputDecoration(
                  labelText: '8D song name',
                  prefixIcon: Icon(Icons.edit_rounded))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading ? null : _pickAudio,
            icon: const Icon(Icons.audio_file_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                  picked == null
                      ? 'Choose MP3 / WAV / FLAC / M4A'
                      : picked!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 18),
          _slider('Pan speed', panSpeed, .3, .7,
              (v) => setState(() => panSpeed = v),
              suffix: '${panSpeed.toStringAsFixed(2)} Hz'),
          _slider('8D intensity', intensity, 0, 1.5,
              (v) => setState(() => intensity = v),
              suffix: intensity.toStringAsFixed(2)),
          _slider('Hall reverb', reverb, .30, .40,
              (v) => setState(() => reverb = v),
              suffix: '${(reverb * 100).round()}%'),
          _slider(
              'Reverb decay', decay, 2.0, 3.0, (v) => setState(() => decay = v),
              suffix: '${decay.toStringAsFixed(1)} s'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: loading ? null : _create,
            icon: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(loading ? 'Creating 8D…' : 'Create 8D Song'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Use audio you created, own, or have permission to convert and save.',
              style: TextStyle(color: Color(0xFF8C7770), fontSize: 12.5)),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          if (result != null) ...[
            const SizedBox(height: 22),
            _resultCard(result!),
          ],
          const SizedBox(height: 30),
          const Text('My 8D Songs',
              style: TextStyle(
                  fontSize: 25, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 4),
          const Text('8D songs you chose to keep in your Catws account.',
              style: TextStyle(color: Color(0xFF8C7770))),
          const SizedBox(height: 12),
          if (loadingLibrary)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator()))
          else if (saved.isEmpty)
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                  color: soft, borderRadius: BorderRadius.circular(18)),
              child: const Text(
                  'No saved 8D songs yet. Create one above and tap “Save to Catws”.',
                  style: TextStyle(color: ink, height: 1.4)),
            )
          else
            ...saved.map(_savedTile),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {required String suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Column(
        children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: ink))),
            Text(suffix,
                style:
                    const TextStyle(color: accent, fontWeight: FontWeight.w700))
          ]),
          Slider(
              value: value,
              min: min,
              max: max,
              onChanged: loading ? null : onChanged),
        ],
      ),
    );
  }

  Widget _resultCard(User8DCreation item) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8C3BB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your 8D song is ready ✨',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 5),
          Text(item.title, style: const TextStyle(fontSize: 16, color: ink)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                  onPressed: () => _preview(item),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Preview')),
              OutlinedButton.icon(
                  onPressed: () => _download(item),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download')),
              if (!item.savedToCatws)
                FilledButton.icon(
                    onPressed: () => _saveToCatws(item),
                    icon: const Icon(Icons.library_add_rounded),
                    label: const Text('Save to Catws'))
              else ...[
                const Chip(
                    avatar: Icon(Icons.check_circle_rounded, size: 18),
                    label: Text('Saved in Catws')),
                OutlinedButton.icon(
                    onPressed: () => _addTo8dPlaylist(item),
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('8D Playlist')),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _savedTile(User8DCreation item) {
    final active = playingId == item.id && player.playing;
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF0EC),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: const Color(0xFFDDB8CF),
            child: Icon(
                active ? Icons.pause_rounded : Icons.spatial_audio_rounded,
                color: const Color(0xFF5D365F))),
        title: Text(item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        subtitle: Text(item.sourceFilename,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _preview(item),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'playlist') _addTo8dPlaylist(item);
            if (value == 'download') _download(item);
            if (value == 'delete') _delete(item);
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
            PopupMenuItem(
                value: 'delete',
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Delete'))),
          ],
        ),
      ),
    );
  }
}
