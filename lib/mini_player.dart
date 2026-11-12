import 'package:flutter/material.dart';

import 'models.dart';
import 'playback.dart';
import 'player_screen.dart';
import 'theme.dart';

/// Small floating bar that stays visible while browsing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final pb = Playback.instance;
    return ListenableBuilder(
      listenable: pb,
      builder: (context, _) {
        final PlayItem? item = pb.current;
        if (item == null) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: kCard2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kAccent.withOpacity(0.4)),
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(gradient: accentGradient, borderRadius: BorderRadius.circular(10)),
                    child: Icon(item.kind == 'audio' ? Icons.music_note_rounded : Icons.movie_outlined,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: pb.hasPrev ? pb.prev : null, icon: const Icon(Icons.skip_previous_rounded)),
                  StreamBuilder<bool>(
                    stream: pb.player.stream.playing,
                    builder: (context, snap) {
                      final playing = snap.data ?? false;
                      return IconButton(
                        onPressed: pb.toggle,
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      );
                    },
                  ),
                  IconButton(onPressed: pb.hasNext ? pb.next : null, icon: const Icon(Icons.skip_next_rounded)),
                  IconButton(onPressed: pb.stop, icon: const Icon(Icons.close_rounded, color: kMuted)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
