import 'models.dart';

final _attr = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

/// Parses an M3U / M3U8 playlist into live channels.
List<Channel> parseM3u(String text, String source) {
  final out = <Channel>[];
  String? name;
  String? group;
  String? logo;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final attrs = {for (final m in _attr.allMatches(line)) m.group(1)!: m.group(2)!};
      final comma = line.lastIndexOf(',');
      final title = comma >= 0 ? line.substring(comma + 1).trim() : '';
      name = attrs['tvg-name'] ?? (title.isEmpty ? null : title);
      group = attrs['group-title'] ?? 'Other';
      logo = attrs['tvg-logo'] ?? '';
    } else if (line.startsWith('#')) {
      continue;
    } else if (line.startsWith('http://') || line.startsWith('https://')) {
      out.add(Channel(
        url: line,
        name: name ?? line,
        group: group ?? 'Other',
        logo: logo ?? '',
        source: source,
      ));
      name = null;
      group = null;
      logo = null;
      if (out.length >= maxChannels) break;
    }
  }
  return out;
}
