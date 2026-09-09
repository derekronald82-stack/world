import 'package:flutter/material.dart';
import '../models/song.dart';

class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  const SongCard({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF2EE),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: const Color(0xFF984D45).withOpacity(.08)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  song.coverUrl,
                  width: 68,
                  height: 68,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 68,
                    height: 68,
                    color: const Color(0xFFE7C5BD),
                    child: const Icon(Icons.music_note_rounded, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF403634))),
                    const SizedBox(height: 4),
                    Text('${song.artist} • ${song.category}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8D7770))),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill_rounded, size: 40, color: Color(0xFF984D45)),
            ],
          ),
        ),
      ),
    );
  }
}
