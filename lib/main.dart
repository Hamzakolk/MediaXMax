import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'image_viewer.dart';
import 'mini_player.dart';
import 'models.dart';
import 'player_screen.dart';
import 'playback.dart';
import 'audio_handler.dart';
import 'device_scan.dart';
import 'store.dart';
import 'package:audio_service/audio_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final store = Store();
  await store.load();
  await AudioService.init(
    builder: () => MediaXAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mediax.media_x_max.playback',
      androidNotificationChannelName: 'Media X Max',
      androidStopForegroundOnPause: true,
    ),
  );
  try {
    await scanDeviceMedia(store);
  } catch (_) {}
  runApp(MediaXApp(store: store));
}

class MediaXApp extends StatelessWidget {
  final Store store;
  const MediaXApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media X Max',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: HomeShell(store: store),
    );
  }
}

class HomeShell extends StatefulWidget {
  final Store store;
  const HomeShell({super.key, required this.store});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: IndexedStack(
              index: tab,
              children: [
                HomeTab(store: widget.store),
                IptvTab(store: widget.store),
                SettingsTab(store: widget.store),
              ],
            ),
          ),
          const Positioned(left: 10, right: 10, bottom: 6, child: MiniPlayer()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: kCard,
        indicatorColor: kAccent.withOpacity(0.25),
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.live_tv_outlined), selectedIcon: Icon(Icons.live_tv), label: 'IPTV'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}

// ---------- Home ----------

class HomeTab extends StatefulWidget {
  final Store store;
  const HomeTab({super.key, required this.store});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String filter = 'all';
  String query = '';

  Future<void> _addFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (res != null) widget.store.addFiles(res.files);
  }

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    final count = await widget.store.addFolder(dir);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added $count files')));
  }

  void _open(Track t, List<Track> shown) {
    if (t.kind == 'image') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewer(path: t.path, name: t.name)));
      return;
    }
    final media = shown.where((x) => x.kind != 'image').toList();
    final queue = [
      for (final x in media)
        PlayItem(
          url: x.path,
          title: x.name,
          subtitle: '${x.kind == 'audio' ? 'Audio' : 'Video'} · ${x.ext.toUpperCase()}',
          isLive: false,
          kind: x.kind,
        ),
    ];
    openPlayer(context, queue, media.indexOf(t));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final all = widget.store.tracks;
        final audio = all.where((t) => t.kind == 'audio').toList();
        final video = all.where((t) => t.kind == 'video').toList();
        final base = filter == 'audio' ? audio : filter == 'video' ? video : all;
        final shown = base
            .where((t) => t.name.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(gradient: accentGradient, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Text('Media X', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const Text(' Max', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kAccent)),
                  const Spacer(),
                  IconButton(onPressed: _addFolder, icon: const Icon(Icons.folder_open_rounded)),
                  IconButton(onPressed: _addFiles, icon: const Icon(Icons.add_rounded)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search',
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final f in const [('all', 'All'), ('audio', 'Music'), ('video', 'Videos')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.$2),
                        selected: filter == f.$1,
                        selectedColor: kAccent,
                        backgroundColor: kCard,
                        labelStyle: TextStyle(color: filter == f.$1 ? Colors.white : kMuted),
                        side: BorderSide.none,
                        onSelected: (_) => setState(() => filter = f.$1),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _BigCard(
                    title: 'My Music',
                    count: audio.length,
                    icon: Icons.music_note_rounded,
                    gradient: const LinearGradient(colors: [Color(0xFFEC4899), kAccent]),
                    onTap: () => setState(() => filter = 'audio'),
                  ),
                  const SizedBox(width: 12),
                  _BigCard(
                    title: 'My Videos',
                    count: video.length,
                    icon: Icons.movie_outlined,
                    gradient: const LinearGradient(colors: [kAccent2, Color(0xFF6366F1)]),
                    onTap: () => setState(() => filter = 'video'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Text('Nothing here yet. Tap + to add files.', style: TextStyle(color: kMuted)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _TrackRow(
                          track: shown[i],
                          index: i,
                          onTap: () => _open(shown[i], shown),
                          onLongPress: () => widget.store.removeTrack(shown[i].path),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BigCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _BigCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 30, color: Colors.white),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('($count)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final Track track;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TrackRow({required this.track, required this.index, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final icon = track.kind == 'audio'
        ? Icons.music_note_rounded
        : track.kind == 'image'
            ? Icons.image_outlined
            : Icons.play_circle_outline;
    final label = track.kind == 'audio' ? 'Audio' : track.kind == 'image' ? 'Image' : 'Video';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(gradient: artFor(index), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('$label · ${track.ext.toUpperCase()}', style: const TextStyle(color: kMuted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.more_vert, color: kMuted),
          ],
        ),
      ),
    );
  }
}

// ---------- IPTV ----------

class IptvTab extends StatefulWidget {
  final Store store;
  const IptvTab({super.key, required this.store});

  @override
  State<IptvTab> createState() => _IptvTabState();
}

class _IptvTabState extends State<IptvTab> {
  String group = '';
  String query = '';

  void _snack(String? err) {
    if (err != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _addM3u() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Add M3U playlist'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'https://...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    _snack(await widget.store.addM3u(url));
  }

  Future<void> _addXtream() async {
    final server = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Add IPTV server'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: server, decoration: const InputDecoration(labelText: 'Server (http://host:port)')),
              TextField(controller: user, decoration: const InputDecoration(labelText: 'Username')),
              TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name (optional)')),
              const SizedBox(height: 8),
              const Text('Use only a service you have an account for.',
                  style: TextStyle(fontSize: 12, color: kMuted)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    _snack(await widget.store.addXtream(server.text, user.text, pass.text, name.text));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final s = widget.store;
        final groups = {for (final c in s.channels) c.group}.toList()..sort();
        final list = s.channels
            .where((c) =>
                (group.isEmpty || c.group == group) &&
                (query.isEmpty || c.name.toLowerCase().contains(query.toLowerCase())))
            .take(500)
            .toList();
        final playables = [
          for (final c in list)
            PlayItem(url: c.url, title: c.name, subtitle: c.group, isLive: true, kind: 'video'),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('IPTV', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(onPressed: _addM3u, icon: const Icon(Icons.link), label: const Text('M3U URL')),
                  OutlinedButton.icon(onPressed: _addXtream, icon: const Icon(Icons.dns), label: const Text('IPTV server')),
                  for (final src in s.sources)
                    InputChip(
                      label: Text('${src.name} · ${src.count}'),
                      onDeleted: () => s.removeSource(src.name),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Search channels',
                        filled: true,
                        fillColor: kCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: group,
                    dropdownColor: kCard,
                    items: [
                      const DropdownMenuItem(value: '', child: Text('All groups')),
                      for (final g in groups.take(300))
                        DropdownMenuItem(
                          value: g,
                          child: SizedBox(width: 110, child: Text(g, overflow: TextOverflow.ellipsis)),
                        ),
                    ],
                    onChanged: (v) => setState(() => group = v ?? ''),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text('Add an M3U playlist or an IPTV server to see channels.',
                            style: TextStyle(color: kMuted)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          childAspectRatio: 1.05,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => openPlayer(context, playables, i),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: c.logo.isNotEmpty
                                        ? Image.network(c.logo,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => _initials(c.name, i))
                                        : _initials(c.name, i),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text(c.group,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: kMuted)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _initials(String name, int i) {
    final text = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    return Center(
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(gradient: artFor(i), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ---------- More ----------

class SettingsTab extends StatelessWidget {
  final Store store;
  const SettingsTab({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('More', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Media X Max', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 4),
              Text('Your Music. Your Video. Your Experience.', style: TextStyle(color: kMuted)),
              SizedBox(height: 10),
              Text('Playback engine: mpv (media_kit)', style: TextStyle(color: kMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
