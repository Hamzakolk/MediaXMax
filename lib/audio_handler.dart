import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'store.dart';

const _channel = MethodChannel('mediaxmax/scan');

String _ext(String path) => path.contains('.') ? path.split('.').last.toLowerCase() : '';

/// Finds music and videos saved on the phone and adds them to the library.
Future<int> scanDeviceMedia(Store store) async {
  final statuses = await [Permission.audio, Permission.videos, Permission.storage].request();
  final granted = statuses.values.any((s) => s.isGranted || s.isLimited);
  if (!granted) return 0;

  final raw = (await _channel.invokeListMethod<dynamic>('scan')) ?? <dynamic>[];
  final found = <Track>[];
  for (final item in raw) {
    final m = item as Map;
    final path = m['path'] as String;
    final kind = m['kind'] as String;
    final title = (m['title'] as String?) ?? path;
    found.add(Track(
      path: path,
      name: title,
      kind: kind,
      ext: _ext(path),
      size: (m['size'] as num?)?.toInt() ?? 0,
    ));
  }
  store.addScanned(found);
  return found.length;
}
