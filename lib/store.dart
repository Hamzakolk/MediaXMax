import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'm3u.dart';
import 'models.dart';

/// Holds the library, IPTV channels and settings, and saves them to a JSON file.
class Store extends ChangeNotifier {
  List<Track> tracks = [];
  List<Channel> channels = [];
  List<Source> sources = [];
  String theme = 'midnight';
  File? _file;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/media_x_max.json');
    if (await _file!.exists()) {
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      tracks = [for (final e in (j['tracks'] ?? []) as List) Track.fromJson(e as Map<String, dynamic>)];
      channels = [for (final e in (j['channels'] ?? []) as List) Channel.fromJson(e as Map<String, dynamic>)];
      sources = [for (final e in (j['sources'] ?? []) as List) Source.fromJson(e as Map<String, dynamic>)];
      theme = (j['theme'] ?? 'midnight') as String;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    if (_file == null) return;
    await _file!.writeAsString(jsonEncode({
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'channels': channels.map((c) => c.toJson()).toList(),
      'sources': sources.map((s) => s.toJson()).toList(),
      'theme': theme,
    }));
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  // ----- local files -----
  void addFiles(List<PlatformFile> files) {
    final byPath = {for (final t in tracks) t.path: t};
    for (final f in files) {
      final path = f.path;
      final kind = path == null ? null : kindOf(path);
      if (path == null || kind == null) continue;
      final name = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
      byPath[path] = Track(
        path: path,
        name: name,
        kind: kind,
        ext: path.substring(path.lastIndexOf('.') + 1).toLowerCase(),
        size: f.size,
      );
    }
    tracks = byPath.values.toList();
    _changed();
  }

  Future<int> addFolder(String dirPath) async {
    var added = 0;
    final byPath = {for (final t in tracks) t.path: t};
    await for (final e in Directory(dirPath).list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final kind = kindOf(e.path);
      if (kind == null) continue;
      final base = e.uri.pathSegments.last;
      final name = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
      byPath[e.path] = Track(
        path: e.path,
        name: name,
        kind: kind,
        ext: e.path.substring(e.path.lastIndexOf('.') + 1).toLowerCase(),
        size: await e.length(),
      );
      added++;
    }
    tracks = byPath.values.toList();
    _changed();
    return added;
  }

  void removeTrack(String path) {
    tracks.removeWhere((t) => t.path == path);
    _changed();
  }

  void setTheme(String value) {
    theme = value;
    _changed();
  }

  // ----- IPTV -----
  String? _storeSource(String name, List<Channel> list) {
    if (list.isEmpty) return 'No channels found.';
    channels.removeWhere((c) => c.source == name);
    sources.removeWhere((s) => s.name == name);
    channels.addAll(list);
    sources.add(Source(name: name, count: list.length));
    _changed();
    return null;
  }

  Future<String?> addM3u(String url) async {
    final clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) return 'Check the playlist address.';
    try {
      final res = await http.get(Uri.parse(clean)).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return 'Could not download that playlist.';
      final uri = Uri.parse(clean);
      final name = '${uri.host}${uri.path}';
      return _storeSource(name.length > 60 ? name.substring(0, 60) : name,
          parseM3u(utf8.decode(res.bodyBytes, allowMalformed: true), name));
    } catch (_) {
      return 'Could not download that playlist.';
    }
  }

  Future<dynamic> _xget(String base, String user, String pass, [String? action]) async {
    var url = '$base/player_api.php?username=${Uri.encodeQueryComponent(user)}'
        '&password=${Uri.encodeQueryComponent(pass)}';
    if (action != null) url += '&action=$action';
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  Future<String?> addXtream(String server, String user, String pass, String name) async {
    final base = server.trim().replaceAll(RegExp(r'/+$'), '');
    if (!base.startsWith('http://') && !base.startsWith('https://')) return 'Check the server address.';
    if (user.trim().isEmpty || pass.isEmpty) return 'Enter username and password.';
    try {
      final info = await _xget(base, user, pass);
      final ui = info is Map ? info['user_info'] : null;
      final auth = ui is Map ? ui['auth'] : null;
      if ('$auth' != '1' && '$auth' != 'true') return 'Wrong username or password.';

      final catsRaw = await _xget(base, user, pass, 'get_live_categories');
      final streamsRaw = await _xget(base, user, pass, 'get_live_streams');
      final cats = catsRaw is List ? catsRaw : <dynamic>[];
      final streams = streamsRaw is List ? streamsRaw : <dynamic>[];

      final groupOf = <String, String>{};
      for (final c in cats) {
        if (c is Map) groupOf['${c['category_id']}'] = '${c['category_name'] ?? 'Other'}';
      }
      final src = name.trim().isNotEmpty ? name.trim() : '${Uri.parse(base).host} ($user)';
      final list = <Channel>[];
      for (final st in streams) {
        if (st is! Map || st['stream_id'] == null) continue;
        final sid = st['stream_id'];
        final url = '$base/live/${Uri.encodeComponent(user)}/${Uri.encodeComponent(pass)}/$sid.ts';
        list.add(Channel(
          url: url,
          name: '${st['name'] ?? 'Channel $sid'}',
          group: groupOf['${st['category_id']}'] ?? 'Other',
          logo: '${st['stream_icon'] ?? ''}',
          source: src,
        ));
        if (list.length >= maxChannels) break;
      }
      return _storeSource(src, list);
    } catch (_) {
      return 'Could not reach that server.';
    }
  }

  void addScanned(List<Track> found) {
    final byPath = {for (final t in tracks) t.path: t};
    for (final t in found) {
      byPath[t.path] = t;
    }
    tracks = byPath.values.toList();
    _changed();
  }

  void removeSource(String name) {
    channels.removeWhere((c) => c.source == name);
    sources.removeWhere((s) => s.name == name);
    _changed();
  }
}
