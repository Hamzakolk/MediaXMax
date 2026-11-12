import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';

const eqBands = [60, 230, 910, 3600, 14000];

const eqPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0],
  'Bass': [6, 4, 0, 0, 0],
  'Rock': [4, 2, -1, 3, 5],
  'Pop': [-1, 2, 4, 2, -1],
  'Vocal': [-2, 0, 4, 4, 1],
};

class LrcLine {
  final Duration time;
  final String text;
  LrcLine(this.time, this.text);
}

final _lrcRe = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\](.*)');

/// Parses synced lyrics (LRC format) that the user provides.
List<LrcLine> parseLrc(String text) {
  final out = <LrcLine>[];
  for (final raw in text.split('\n')) {
    final m = _lrcRe.firstMatch(raw.trim());
    if (m == null) continue;
    final ms = int.parse((m.group(3) ?? '0').padRight(3, '0'));
    out.add(LrcLine(
      Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms),
      m.group(4)!.trim(),
    ));
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// One shared player for the whole app, so the mini player keeps playing while you browse.
class Playback extends ChangeNotifier {
  Playback._() {
    _sub = player.stream.completed.listen(_onCompleted);
  }

  static final Playback instance = Playback._();

  final Player player = Player();
  late final VideoController controller = VideoController(player);
  StreamSubscription<bool>? _sub;

  List<PlayItem> queue = [];
  int index = -1;
  List<LrcLine> lyrics = [];
  List<double> eq = List.filled(eqBands.length, 0.0);
  Timer? _sleepTimer;
  DateTime? sleepEndsAt;

  PlayItem? get current => (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get hasPrev => index > 0;
  bool get hasNext => index < queue.length - 1;

  void playQueue(List<PlayItem> items, int i) {
    queue = items;
    index = i;
    _load();
  }

  void _load() {
    final c = current;
    if (c == null) return;
    lyrics = [];
    player.open(Media(c.url));
    _applyEq();
    _loadLyrics(c);
    notifyListeners();
  }

  void _onCompleted(bool done) {
    if (done && current != null && !current!.isLive && hasNext) {
      index++;
      _load();
    }
  }

  void next() {
    if (hasNext) {
      index++;
      _load();
    }
  }

  void prev() {
    if (player.state.position.inSeconds > 3) {
      player.seek(Duration.zero);
    } else if (hasPrev) {
      index--;
      _load();
    }
  }

  void toggle() => player.playOrPause();

  void stop() {
    player.stop();
    queue = [];
    index = -1;
    lyrics = [];
    notifyListeners();
  }

  // ----- lyrics -----
  Future<void> _loadLyrics(PlayItem c) async {
    if (c.isLive || c.url.startsWith('http')) return;
    final lrc = File(c.url.replaceAll(RegExp(r'\.[^./\\]+$'), '.lrc'));
    try {
      if (await lrc.exists()) {
        lyrics = parseLrc(await lrc.readAsString());
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> loadLyricsFile(String path) async {
    lyrics = parseLrc(await File(path).readAsString());
    notifyListeners();
  }

  // ----- equalizer -----
  void setEq(List<double> gains) {
    eq = List.of(gains);
    _applyEq();
    notifyListeners();
  }

  void _applyEq() {
    final p = player.platform;
    if (p is NativePlayer) {
      final active = eq.any((g) => g != 0);
      final filters = [
        for (var i = 0; i < eqBands.length; i++)
          'equalizer=f=${eqBands[i]}:width_type=o:width=2:g=${eq[i].toStringAsFixed(1)}',
      ];
      p.setProperty('af', active ? 'lavfi=[${filters.join(',')}]' : '');
    }
  }

  // ----- sleep timer -----
  void setSleep(Duration? d) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepEndsAt = d == null ? null : DateTime.now().add(d);
    if (d != null) {
      _sleepTimer = Timer(d, () {
        player.pause();
        sleepEndsAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }
}
