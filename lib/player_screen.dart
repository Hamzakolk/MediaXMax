import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';

String fmt(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String p(int x) => x.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(sec)}' : '$m:${p(sec)}';
}

class PlayerScreen extends StatefulWidget {
  final List<PlayItem> queue;
  final int index;

  const PlayerScreen({super.key, required this.queue, required this.index});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  late int index = widget.index;

  PlayItem get current => widget.queue[index];

  @override
  void initState() {
    super.initState();
    _open();
    // Move to the next item when a file finishes (not for live channels).
    player.stream.completed.listen((done) {
      if (done && !current.isLive && index < widget.queue.length - 1) _go(index + 1);
    });
  }

  void _open() {
    player.open(Media(current.url));
  }

  void _go(int i) {
    if (i < 0 || i >= widget.queue.length) return;
    setState(() => index = i);
    _open();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = current;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (item.isLive)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
              child: const Text('LIVE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: item.kind == 'audio'
                ? Center(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.secondary,
                        ]),
                      ),
                      child: const Icon(Icons.music_note, size: 80, color: Colors.white),
                    ),
                  )
                : Video(controller: controller, controls: NoVideoControls),
          ),
          _Controls(
            player: player,
            item: item,
            onPrev: () => _go(index - 1),
            onNext: () => _go(index + 1),
            hasPrev: index > 0,
            hasNext: index < widget.queue.length - 1,
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatefulWidget {
  final Player player;
  final PlayItem item;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool hasPrev;
  final bool hasNext;

  const _Controls({
    required this.player,
    required this.item,
    required this.onPrev,
    required this.onNext,
    required this.hasPrev,
    required this.hasNext,
  });

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  double? dragValue;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    return Container(
      color: const Color(0xFF12121C),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: p.stream.position,
            builder: (context, posSnap) {
              return StreamBuilder<Duration>(
                stream: p.stream.duration,
                builder: (context, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  final max = dur.inMilliseconds.toDouble();
                  final value = dragValue ?? pos.inMilliseconds.toDouble().clamp(0.0, max <= 0 ? 1.0 : max).toDouble();
                  return Row(
                    children: [
                      Text(widget.item.isLive ? 'LIVE' : fmt(pos), style: const TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: widget.item.isLive || max <= 0 ? 0.0 : value,
                          max: max <= 0 ? 1.0 : max,
                          onChangeStart: widget.item.isLive ? null : (v) => setState(() => dragValue = v),
                          onChanged: widget.item.isLive ? null : (v) => setState(() => dragValue = v),
                          onChangeEnd: widget.item.isLive
                              ? null
                              : (v) {
                                  p.seek(Duration(milliseconds: v.round()));
                                  setState(() => dragValue = null);
                                },
                        ),
                      ),
                      Text(widget.item.isLive ? '' : fmt(dur), style: const TextStyle(fontSize: 12)),
                    ],
                  );
                },
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: widget.hasPrev ? widget.onPrev : null, icon: const Icon(Icons.skip_previous)),
              StreamBuilder<bool>(
                stream: p.stream.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? false;
                  return IconButton.filled(
                    iconSize: 32,
                    onPressed: p.playOrPause,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  );
                },
              ),
              IconButton(onPressed: widget.hasNext ? widget.onNext : null, icon: const Icon(Icons.skip_next)),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                icon: const Icon(Icons.speed),
                onSelected: (v) => p.setRate(v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0.5, child: Text('0.5x')),
                  PopupMenuItem(value: 1.0, child: Text('1x')),
                  PopupMenuItem(value: 1.25, child: Text('1.25x')),
                  PopupMenuItem(value: 1.5, child: Text('1.5x')),
                  PopupMenuItem(value: 2.0, child: Text('2x')),
                ],
              ),
            ],
          ),
          StreamBuilder<double>(
            stream: p.stream.volume,
            builder: (context, snap) {
              return Row(
                children: [
                  const Icon(Icons.volume_up, size: 18),
                  Expanded(
                    child: Slider(
                      value: (snap.data ?? 100.0).clamp(0.0, 130.0).toDouble(),
                      min: 0,
                      max: 130,
                      onChanged: (v) => p.setVolume(v),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
