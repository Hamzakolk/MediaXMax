import 'package:flutter/material.dart';

import 'playback.dart';
import 'theme.dart';

/// Equalizer: 5 bands with presets.
Future<void> showEqualizer(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    isScrollControlled: true,
    builder: (_) => const _EqSheet(),
  );
}

class _EqSheet extends StatefulWidget {
  const _EqSheet();

  @override
  State<_EqSheet> createState() => _EqSheetState();
}

class _EqSheetState extends State<_EqSheet> {
  late List<double> gains = List.of(Playback.instance.eq);

  void _set(List<double> v) {
    setState(() => gains = v);
    Playback.instance.setEq(v);
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['60Hz', '230Hz', '910Hz', '3.6k', '14k'];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Equalizer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final name in eqPresets.keys)
                  ChoiceChip(
                    label: Text(name),
                    selected: false,
                    backgroundColor: kCard2,
                    onSelected: (_) => _set(List.of(eqPresets[name]!)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  for (var i = 0; i < gains.length; i++)
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: kAccent,
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: Colors.white,
                                  overlayShape: SliderComponentShape.noOverlay,
                                ),
                                child: Slider(
                                  min: -12,
                                  max: 12,
                                  value: gains[i],
                                  onChanged: (v) {
                                    final next = List.of(gains)..[i] = v;
                                    _set(next);
                                  },
                                ),
                              ),
                            ),
                          ),
                          Text(labels[i], style: const TextStyle(color: kMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sleep timer: pauses playback after the chosen time.
Future<void> showSleepTimer(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: kCard,
    builder: (ctx) {
      final options = <String, Duration?>{
        'Off': null,
        '5 minutes': const Duration(minutes: 5),
        '15 minutes': const Duration(minutes: 15),
        '30 minutes': const Duration(minutes: 30),
        '60 minutes': const Duration(minutes: 60),
      };
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sleep timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.key),
                onTap: () {
                  Playback.instance.setSleep(e.value);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      );
    },
  );
}
