import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';
import 'playback.dart';
import 'player_sheets.dart';
import 'theme.dart';

String fmt(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String p(int x) => x.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(sec)}' : '$m:${p(sec)}';
}

/// Opens the full player for a queue. Used by the library and IPTV screens.
void openPlayer(BuildContext context, List<PlayItem> queue, int index) {
  Playback.instance.playQueue(queue, index);
  Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  int tab = 0; // 0 = now playing, 1 = lyrics

  @override
  Widget build(BuildContext context) {
    final pb = Playback.instance;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: pb,
          builder: (context, _) {
            final item = pb.current;
            if (item == null) {
              return const Center(child: Text('Nothing playing', style: TextStyle(color: kMuted)));
            }
            final audio = item.kind == 'audio';
            return Column(
              children: [
                _Header(item: item, audio: audio),
                if (audio) _Tabs(tab: tab, onChanged: (t) => setState(() => tab = t)),
                Expanded(
                  child: audio
                      ? (tab == 0 ? _ArtBlock(item: item, index: pb.index) : const _LyricsView())
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Video(controller: pb.controller, controls: NoVideoControls),
                          ),
                        ),
                ),
                const _Controls(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PlayItem item;
  final bool audio;
  const _Header({required this.item, required this.audio});

  @override
  Widget build(BuildContext context) {
    final sleepEnds = Playback.instance.sleepEndsAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              audio ? 'Now Playing' : item.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (item.isLive)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
              child: const Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          if (sleepEnds != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(fmt(sleepEnds.difference(DateTime.now())),
                  style: const TextStyle(color: kAccent, fontSize: 12)),
            ),
          IconButton(icon: const Icon(Icons.bedtime_outlined), onPressed: () => showSleepTimer(context)),
          IconButton(icon: const Icon(Icons.tune_rounded), onPressed: () => showEqualizer(context)),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onChanged;
  const _Tabs({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tabText(String label, int i) => Expanded(
          child: InkWell(
            onTap: () => onChanged(i),
            child: Column(
              children: [
                Text(label,
                    style: TextStyle(
                      color: tab == i ? Colors.white : kMuted,
                      fontWeight: tab == i ? FontWeight.bold : FontWeight.normal,
                    )),
                const SizedBox(height: 6),
                Container(height: 3, width: 60, color: tab == i ? kAccent : Colors.transparent),
              ],
            ),
          ),
        );
    return Row(children: [tabText('Now Playing', 0), tabText('Lyrics', 1)]);
  }
}

class _ArtBlock extends StatelessWidget {
  final PlayItem item;
  final int index;
  const _ArtBlock({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: artFor(max(index, 0)),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [BoxShadow(color: kAccent.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: const Center(child: Icon(Icons.music_note_rounded, size: 96, color: Colors.white)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(item.subtitle, style: const TextStyle(color: kMuted)),
        ],
      ),
    );
  }
}

class _LyricsView extends StatefulWidget {
  const _LyricsView();

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final ScrollController scroll = ScrollController();
  static const double rowHeight = 48;

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['lrc', 'txt']);
    final path = res?.files.single.path;
    if (path != null) await Playback.instance.loadLyricsFile(path);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pb = Playback.instance;
    if (pb.lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No lyrics file found.\nPut a .lrc file with the same name next to the song, or pick one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kMuted),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _pick, child: const Text('Pick .lrc file')),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<Duration>(
      stream: pb.player.stream.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        var active = 0;
        for (var i = 0; i < pb.lyrics.length; i++) {
          if (pb.lyrics[i].time <= pos) active = i;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) {
            scroll.animateTo(max(0, active * rowHeight - 120),
                duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
        return ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
          itemCount: pb.lyrics.length,
          itemBuilder: (context, i) {
            final isActive = i == active;
            return SizedBox(
              height: rowHeight,
              child: Center(
                child: Text(
                  pb.lyrics[i].text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isActive ? 20 : 16,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? Colors.white : kMuted,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Controls extends StatefulWidget {
  const _Controls();

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  double? dragValue;

  @override
  Widget build(BuildContext context) {
    final pb = Playback.instance;
    final p = pb.player;
    final item = pb.current;
    final audio = item?.kind == 'audio';
    final live = item?.isLive ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (audio)
            SizedBox(height: 44, width: double.infinity, child: CustomPaint(painter: _WavePainter())),
          StreamBuilder<Duration>(
            stream: p.stream.position,
            builder: (context, posSnap) => StreamBuilder<Duration>(
              stream: p.stream.duration,
              builder: (context, durSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = durSnap.data ?? Duration.zero;
                final max = dur.inMilliseconds.toDouble();
                final value = dragValue ?? pos.inMilliseconds.toDouble().clamp(0.0, max <= 0 ? 1.0 : max).toDouble();
                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: kAccent,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        trackHeight: 4,
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: live || max <= 0 ? 0.0 : value,
                        max: max <= 0 ? 1.0 : max,
                        onChanged: live ? null : (v) => setState(() => dragValue = v),
                        onChangeEnd: live
                            ? null
                            : (v) {
                                p.seek(Duration(milliseconds: v.round()));
                                setState(() => dragValue = null);
                              },
                      ),
                    ),
                    Row(
                      children: [
                        Text(live ? 'LIVE' : fmt(pos), style: const TextStyle(color: kMuted, fontSize: 12)),
                        const Spacer(),
                        Text(live ? '' : fmt(dur), style: const TextStyle(color: kMuted, fontSize: 12)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: pb.hasPrev ? pb.prev : null,
                icon: const Icon(Icons.skip_previous_rounded, size: 34),
              ),
              StreamBuilder<bool>(
                stream: p.stream.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? false;
                  return Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(gradient: accentGradient, shape: BoxShape.circle),
                    child: IconButton(
                      onPressed: pb.toggle,
                      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 40, color: Colors.white),
                    ),
                  );
                },
              ),
              IconButton(
                onPressed: pb.hasNext ? pb.next : null,
                icon: const Icon(Icons.skip_next_rounded, size: 34),
              ),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                icon: const Icon(Icons.speed_rounded),
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
                  const Icon(Icons.volume_up_rounded, size: 18, color: kMuted),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: kAccent2,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        trackHeight: 3,
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: (snap.data ?? 100.0).clamp(0.0, 130.0).toDouble(),
                        min: 0,
                        max: 130,
                        onChanged: (v) => p.setVolume(v),
                      ),
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

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const bars = 48;
    final w = size.width / bars;
    final paint = Paint()
      ..shader = const LinearGradient(colors: [kAccent, kAccent2]).createShader(Offset.zero & size);
    for (var i = 0; i < bars; i++) {
      final h = (sin(i * 0.55) * 0.4 + sin(i * 0.23) * 0.3 + 0.7).clamp(0.15, 1.0) * size.height;
      final x = i * w + w / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, size.height / 2), width: w * 0.55, height: h),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
