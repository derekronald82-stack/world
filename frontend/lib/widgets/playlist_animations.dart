import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A quiet, Spotify-inspired motion layer for the player screen.
///
/// It is isolated behind a RepaintBoundary so progress updates do not make
/// the rest of the player UI repaint.
class AnimatedAudioBackdrop extends StatefulWidget {
  const AnimatedAudioBackdrop({
    super.key,
    required this.playbackStream,
  });

  final Stream<bool> playbackStream;

  @override
  State<AnimatedAudioBackdrop> createState() => _AnimatedAudioBackdropState();
}

class _AnimatedAudioBackdropState extends State<AnimatedAudioBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  void _syncPlayback(bool isPlaying) {
    if (_isPlaying == isPlaying) return;
    _isPlaying = isPlaying;
    if (isPlaying) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: widget.playbackStream,
      initialData: false,
      builder: (context, snapshot) {
        _syncPlayback(snapshot.data ?? false);
        return IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _AudioBackdropPainter(
                  progress: _controller.value,
                  active: _isPlaying,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AudioBackdropPainter extends CustomPainter {
  const _AudioBackdropPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * math.pi * 2;
    final base = Paint()..color = const Color(0xFFFFFAF7);
    canvas.drawRect(Offset.zero & size, base);

    final opacity = active ? .16 : .08;
    final blobs = [
      (
        Offset(size.width * (.18 + math.sin(t) * .06),
            size.height * (.22 + math.cos(t * .8) * .05)),
        size.width * .52,
        const Color(0xFFFFB39F),
      ),
      (
        Offset(size.width * (.86 + math.cos(t * .72) * .06),
            size.height * (.48 + math.sin(t * .9) * .08)),
        size.width * .48,
        const Color(0xFFB9D8D0),
      ),
      (
        Offset(size.width * (.35 + math.sin(t * .55) * .08),
            size.height * (.92 + math.cos(t * .6) * .04)),
        size.width * .58,
        const Color(0xFFD6B8E4),
      ),
    ];

    for (final blob in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [blob.$3.withOpacity(opacity), Colors.transparent],
        ).createShader(Rect.fromCircle(center: blob.$1, radius: blob.$2));
      canvas.drawCircle(blob.$1, blob.$2, paint);
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF984D45).withOpacity(active ? .08 : .035);
    final center = Offset(size.width * .5, size.height * .33);
    for (var i = 0; i < 3; i++) {
      final radius = size.width * (.35 + i * .13) +
          (active ? math.sin(t + i) * 12 : 0);
      canvas.drawCircle(center, radius, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _AudioBackdropPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active;
}

Future<String?> showAnimatedPlaylistNameDialog(
  BuildContext context, {
  required String title,
}) async {
  final controller = TextEditingController();
  try {
    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close playlist dialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(hintText: 'Playlist name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

class PlaylistRoute<T> extends PageRouteBuilder<T> {
  PlaylistRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 430),
          reverseTransitionDuration: const Duration(milliseconds: 330),
          opaque: false,
          barrierColor: Colors.transparent,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            final fade = FadeTransition(
              opacity: curve,
              child: child,
            );

            final slide = SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(curve),
              child: fade,
            );

            return ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1)
                  .chain(
                    CurveTween(curve: Curves.easeOutCubic),
                  )
                  .animate(curve),
              child: slide,
            );
          },
        );
}

class PlaylistHeroCover extends StatelessWidget {
  const PlaylistHeroCover({
    super.key,
    required this.tag,
    this.coverUrl,
    this.size = 160,
    this.borderRadius,
    this.backgroundColor = const Color(0xFFFFE2D9),
    this.icon = Icons.queue_music_rounded,
  });

  final String tag;
  final String? coverUrl;
  final double size;
  final BorderRadiusGeometry? borderRadius;
  final Color backgroundColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(18);
    final child = ClipRRect(
      borderRadius: radius,
      child: coverUrl != null && coverUrl!.isNotEmpty
          ? Image.network(
              coverUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );

    // This widget owns the single Hero wrapper. Callers must not wrap it in a
    // second Hero with the same tag, otherwise Flutter throws a duplicate-tag
    // exception during the route flight.
    return Hero(
      tag: tag,
      child: RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: child,
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              backgroundColor,
              const Color(0xFFD8B7AE),
            ],
          ),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF704F4A),
          size: size * 0.36,
        ),
      );
}

class AnimatedPlaylistHeader extends StatefulWidget {
  const AnimatedPlaylistHeader({
    super.key,
    required this.tag,
    required this.title,
    required this.owner,
    required this.meta,
    this.coverUrl,
    this.onPlay,
    this.onShuffle,
    this.backgroundColor = const Color(0xFFFFFAF7),
    this.accent = const Color(0xFF984D45),
    this.icon = Icons.queue_music_rounded,
  });

  final String tag;
  final String title;
  final String owner;
  final String meta;
  final String? coverUrl;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final Color backgroundColor;
  final Color accent;
  final IconData icon;

  @override
  State<AnimatedPlaylistHeader> createState() => _AnimatedPlaylistHeaderState();
}

class _AnimatedPlaylistHeaderState extends State<AnimatedPlaylistHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    final artworkScale = Tween<double>(begin: 0.84, end: 1)
        .chain(
          CurveTween(
              curve: const Interval(0, 0.45, curve: Curves.easeOutCubic)),
        )
        .animate(animation);

    final textFade = Tween<double>(begin: 0, end: 1)
        .chain(
          CurveTween(
              curve: const Interval(0.15, 0.55, curve: Curves.easeOutCubic)),
        )
        .animate(animation);

    final buttonFade = Tween<double>(begin: 0, end: 1)
        .chain(
          CurveTween(
              curve: const Interval(0.22, 0.7, curve: Curves.easeOutCubic)),
        )
        .animate(animation);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 30),
          color: widget.backgroundColor,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Transform.scale(
                  scale: artworkScale.value,
                  child: PlaylistHeroCover(
                    tag: widget.tag,
                    coverUrl: widget.coverUrl,
                    size: 170,
                    borderRadius: BorderRadius.circular(24),
                    icon: widget.icon,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FadeTransition(
                opacity: textFade,
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF403634),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FadeTransition(
                opacity: textFade,
                child: Text(
                  widget.owner,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF8C736E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: textFade,
                child: Text(
                  widget.meta,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6F5C57),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FadeTransition(
                opacity: buttonFade,
                child: Transform.scale(
                  scale: 0.9 + (buttonFade.value * 0.1),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: widget.onPlay,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: widget.onShuffle,
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF403634),
                          side: const BorderSide(color: Color(0xFFDAC0B9)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PlaylistSongEntrance extends StatefulWidget {
  const PlaylistSongEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<PlaylistSongEntrance> createState() => _PlaylistSongEntranceState();
}

class _PlaylistSongEntranceState extends State<PlaylistSongEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    // Only the initial viewport gets a stagger. Off-screen rows are ready
    // immediately, avoiding a long delayed animation for large playlists.
    if (widget.index >= 12) {
      _controller.value = 1;
    } else {
      final delay = Duration(milliseconds: 70 + widget.index * 32);
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return RepaintBoundary(
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: widget.child,
        ),
      ),
    );
  }
}
