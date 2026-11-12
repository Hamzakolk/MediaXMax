import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'models.dart';
import 'player_screen.dart';
import 'store.dart';

const themeColors = {
  'midnight': Color(0xFF1E88FF),
  'crimson': Color(0xFFE5484D),
  'emerald': Color(0xFF2ECC71),
  'amber': Color(0xFFF5A524),
  'mono': Color(0xFF8A93B0),
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(MediaXApp(store: store));
}

class MediaXApp extends StatelessWidget {
  final Store store;
  const MediaXApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Media X Max',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: themeColors[store.theme] ?? themeColors['midnight'],
        ),
        home: HomePage(store: store),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final Store store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryPage(store: widget.store),
      IptvPage(store: widget.store),
      SettingsPage(store: widget.store),
    ];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.video_library_outlined), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.live_tv_outlined), label: 'IPTV'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  final Store store;
  const LibraryPage({super.key, required this.store});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
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

  @override
  Widget build(BuildContext context) {
    final items = widget.store.tracks
        .where((t) => t.name.toLowerCase().contains(query.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final playables = [
      for (final t in items)
        Playable(url: t.path, title: t.name, subtitle: '${t.kind == 'audio' ? 'Audio' : 'Video'} · ${t.ext.toUpperCase()}',
            isLive: false, kind: t.kind),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media X Max'),
        actions: [
          IconButton(onPressed: _addFolder, icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'Add folder'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFiles,
        icon: const Icon(Icons.add),
        label: const Text('Add files'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search your library'),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Nothing here yet. Tap "Add files".'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final t = items[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PlayerScreen(queue: playables, index: i)),
                        ),
                        onLongPress: () => widget.store.removeTrack(t.path),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: LinearGradient(colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.tertiary,
                                  ]),
                                ),
                                child: Center(
                                  child: Icon(t.kind == 'audio' ? Icons.music_note : Icons.play_circle_outline,
                                      size: 40, color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(t.ext.toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class IptvPage extends StatefulWidget {
  final Store store;
  const IptvPage({super.key, required this.store});

  @override
  State<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends State<IptvPage> {
  String group = '';
  String query = '';

  Future<void> _addM3u() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add M3U playlist'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'https://...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    final err = await widget.store.addM3u(url);
    if (err != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _addXtream() async {
    final server = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
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
    final err = await widget.store.addXtream(server.text, user.text, pass.text, name.text);
    if (err != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final groups = {for (final c in s.channels) c.group}.toList()..sort();
    final list = s.channels
        .where((c) => (group.isEmpty || c.group == group) &&
            (query.isEmpty || c.name.toLowerCase().contains(query.toLowerCase())))
        .take(500)
        .toList();
    final playables = [
      for (final c in list) Playable(url: c.url, title: c.name, subtitle: c.group, isLive: true, kind: 'video'),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search channels'),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: group.isEmpty ? '' : group,
                items: [
                  const DropdownMenuItem(value: '', child: Text('All groups')),
                  for (final g in groups.take(300)) DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => group = v ?? ''),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Add an M3U playlist or an IPTV server to see channels.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final c = list[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PlayerScreen(queue: playables, index: i)),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.white.withOpacity(0.05),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: c.logo.isNotEmpty
                                  ? Image.network(c.logo, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 36))
                                  : const Icon(Icons.tv, size: 36),
                            ),
                            const SizedBox(height: 6),
                            Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(c.group, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  final Store store;
  const SettingsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Theme'),
          trailing: DropdownButton<String>(
            value: store.theme,
            items: const [
              DropdownMenuItem(value: 'midnight', child: Text('Midnight')),
              DropdownMenuItem(value: 'crimson', child: Text('Crimson')),
              DropdownMenuItem(value: 'emerald', child: Text('Emerald')),
              DropdownMenuItem(value: 'amber', child: Text('Amber')),
              DropdownMenuItem(value: 'mono', child: Text('Mono')),
            ],
            onChanged: (v) {
              if (v != null) store.setTheme(v);
            },
          ),
        ),
        const Divider(),
        const ListTile(
          title: Text('Media X Max'),
          subtitle: Text('Android · playback engine: mpv (media_kit)'),
        ),
      ],
    );
  }
}
