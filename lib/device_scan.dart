import 'package:on_audio_query/on_audio_query.dart';

import 'models.dart';
import 'store.dart';

/// Finds music and videos saved on the phone (MediaStore) and adds them to the library.
Future<int> scanDeviceMedia(Store store) async {
  final query = OnAudioQuery();
  final granted = await query.permissionsRequest();
  if (!granted) return 0;

  final found = <Track>[];

  final songs = await query.querySongs(
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
    ignoreCase: true,
  );
  for (final s in songs) {
    final path = s.data;
    final kind = kindOf(path);
    if (kind == null) continue;
    found.add(Track(
      path: path,
      name: s.title,
      kind: kind,
      ext: path.split('.').last.toLowerCase(),
      size: s.size,
    ));
  }

  final videos = await query.queryVideos(
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
    ignoreCase: true,
  );
  for (final v in videos) {
    final path = v.data;
    final kind = kindOf(path);
    if (kind == null) continue;
    found.add(Track(
      path: path,
      name: v.title,
      kind: kind,
      ext: path.split('.').last.toLowerCase(),
      size: v.size,
    ));
  }

  store.addScanned(found);
  return found.length;
}
