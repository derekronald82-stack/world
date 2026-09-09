import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/local_library_store.dart';
import 'eightd_library_screen.dart';
import 'catalog_screen.dart';

class MusicLibraryHubScreen extends StatelessWidget {
  final ApiClient api;
  final LocalLibraryStore localLibrary;
  final bool showPrivateEightD;
  const MusicLibraryHubScreen({
    super.key,
    required this.api,
    required this.localLibrary,
    this.showPrivateEightD = false,
  });

  static const bg = Color(0xFFFFFAF7);
  static const ink = Color(0xFF403634);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
          title: const Text('Your Music Library',
              style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
        children: [
          const Text('Choose a library',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 6),
          const Text(
              'Public catalog music and your private 8D creations are kept separate.',
              style: TextStyle(color: Color(0xFF806D67), height: 1.4)),
          const SizedBox(height: 22),
          _option(
            context,
            number: 'OPTION 1',
            title: 'Normal Songs',
            subtitle: 'Admin catalog • Normal songs',
            icon: Icons.library_music_rounded,
            colors: const [Color(0xFFFFE1DA), Color(0xFFFFF1ED)],
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CatalogScreen(
                          api: api,
                          songType: 'normal',
                          localLibrary: localLibrary,
                          remoteLibraryEnabled: showPrivateEightD,
                        ))),
          ),
          const SizedBox(height: 16),
          _option(
            context,
            number: 'OPTION 2',
            title: 'Public 8D Songs',
            subtitle: 'Admin catalog • Headphones recommended',
            icon: Icons.spatial_audio_rounded,
            colors: const [Color(0xFFE6D8F3), Color(0xFFF8EFFC)],
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CatalogScreen(
                          api: api,
                          songType: '8d',
                          localLibrary: localLibrary,
                          remoteLibraryEnabled: showPrivateEightD,
                        ))),
          ),
          if (showPrivateEightD) ...[
            const SizedBox(height: 16),
            _option(
              context,
              number: 'OPTION 3',
              title: 'My 8D Songs',
              subtitle: 'Private generated songs and 8D playlists',
              icon: Icons.headphones_rounded,
              colors: const [Color(0xFFE6D8F3), Color(0xFFF8EFFC)],
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EightDLibraryScreen(api: api))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required String number,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Ink(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.black.withOpacity(.04)),
        ),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.82), shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: const Color(0xFF6D4C4A)),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(number,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: Color(0xFF9A6A64))),
                  const SizedBox(height: 4),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: ink)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF76635F), height: 1.35)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 30, color: Color(0xFF806D67)),
          ],
        ),
      ),
    );
  }
}
