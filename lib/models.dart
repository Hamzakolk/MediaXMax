const int maxChannels = 20000;

const videoExt = {
  'mp4', 'mkv', 'webm', 'mov', 'avi', 'wmv', 'm4v', 'mpg', 'mpeg', 'ts', 'm2ts', '3gp', 'ogv', 'flv'
};
const audioExt = {
  'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'aiff', 'alac', 'ape', 'mka'
};

String? kindOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = path.substring(dot + 1).toLowerCase();
  if (videoExt.contains(ext)) return 'video';
  if (audioExt.contains(ext)) return 'audio';
  return null;
}

class Track {
  final String path;
  final String name;
  final String kind;
  final String ext;
  final int size;

  Track({required this.path, required this.name, required this.kind, required this.ext, required this.size});

  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'kind': kind, 'ext': ext, 'size': size};

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        path: j['path'] ?? '',
        name: j['name'] ?? '',
        kind: j['kind'] ?? 'video',
        ext: j['ext'] ?? '',
        size: j['size'] ?? 0,
      );
}

class Channel {
  final String url;
  final String name;
  final String group;
  final String logo;
  final String source;

  Channel({required this.url, required this.name, required this.group, required this.logo, required this.source});

  Map<String, dynamic> toJson() => {'url': url, 'name': name, 'group': group, 'logo': logo, 'source': source};

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        url: j['url'] ?? '',
        name: j['name'] ?? '',
        group: j['group'] ?? 'Other',
        logo: j['logo'] ?? '',
        source: j['source'] ?? '',
      );
}

class Source {
  final String name;
  final int count;

  Source({required this.name, required this.count});

  Map<String, dynamic> toJson() => {'name': name, 'count': count};

  factory Source.fromJson(Map<String, dynamic> j) => Source(name: j['name'] ?? '', count: j['count'] ?? 0);
}

/// One thing the player can open: a local file or a live channel.
class PlayItem {
  final String url;
  final String title;
  final String subtitle;
  final bool isLive;
  final String kind;

  PlayItem({required this.url, required this.title, required this.subtitle, required this.isLive, required this.kind});
}
