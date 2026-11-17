import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'app_settings.dart';
import 'library.dart';
import 'player_page.dart';
import 'settings_page.dart';
import 'update_service.dart';

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

Future<void> playItems(BuildContext context, List<VideoItem> items, int index) async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PlayerPage(items: items, index: index)),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    if (AppSettings.autoUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final info = await UpdateService.check();
        if (info != null && mounted) showUpdateDialog(context, info);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const _VideosTab(), const _NetworkTab(), const SettingsPage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library_rounded), label: 'Videos'),
          NavigationDestination(icon: Icon(Icons.language_rounded), label: 'Network'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

// ---------------- Videos tab: folders ----------------
class _VideosTab extends StatefulWidget {
  const _VideosTab();
  @override
  State<_VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<_VideosTab> {
  late Future<LibraryResult> future = VideoLibrary.load();

  void _reload() => setState(() => future = VideoLibrary.load());

  Future<void> _openFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    final f = res?.files.single;
    if (f?.path == null) return;
    final item = VideoItem(title: f!.name, path: f.path);
    if (!mounted) return;
    await playItems(context, [item], 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('Dew Player', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
              IconButton(onPressed: _openFile, icon: const Icon(Icons.folder_open_rounded), tooltip: 'Open file'),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<LibraryResult>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final r = snap.data ?? LibraryResult([]);
              if (r.denied) {
                return _Empty(
                  icon: Icons.lock_outline_rounded,
                  text: 'Allow access to videos to see them here',
                  action: 'Allow',
                  onAction: () async {
                    final ps = await PhotoManager.requestPermissionExtend();
                    if (ps.hasAccess) {
                      _reload();
                    } else {
                      await PhotoManager.openSetting();
                    }
                  },
                );
              }
              if (r.folders.isEmpty) {
                return _Empty(
                  icon: Icons.video_file_outlined,
                  text: 'No videos found',
                  action: 'Open a file',
                  onAction: _openFile,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  itemCount: r.folders.length,
                  itemBuilder: (_, i) {
                    final f = r.folders[i];
                    return ListTile(
                      leading: Icon(Icons.folder_rounded, size: 36, color: Theme.of(context).colorScheme.primary),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${f.videos.length} video${f.videos.length == 1 ? '' : 's'}'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FolderPage(folder: f)),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;
  const _Empty({required this.icon, required this.text, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).hintColor),
          const SizedBox(height: 12),
          Text(text),
          const SizedBox(height: 12),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class FolderPage extends StatelessWidget {
  final VideoFolder folder;
  const FolderPage({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(folder.name)),
      body: ListView.builder(
        itemCount: folder.videos.length,
        itemBuilder: (context, i) {
          final v = folder.videos[i];
          return ListTile(
            leading: _Thumb(item: v),
            title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: v.duration == null ? null : Text(fmtDuration(v.duration!)),
            onTap: () => playItems(context, folder.videos, i),
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final VideoItem item;
  const _Thumb({required this.item});

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    );
    if (item.asset == null) {
      return Container(
        width: 96,
        height: 60,
        decoration: box,
        child: const Icon(Icons.play_circle_outline_rounded),
      );
    }
    return Container(
      width: 96,
      height: 60,
      decoration: box,
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder(
        future: item.thumbnail(),
        builder: (_, snap) {
          final data = snap.data;
          if (data == null) return const Icon(Icons.play_circle_outline_rounded);
          return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
        },
      ),
    );
  }
}

// ---------------- Network tab ----------------
class _NetworkTab extends StatefulWidget {
  const _NetworkTab();
  @override
  State<_NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<_NetworkTab> {
  final url = TextEditingController();
  List<RecentItem> recent = AppSettings.recent;

  Future<void> _play(String src) async {
    final s = src.trim();
    if (s.isEmpty) return;
    final title = s.split('/').where((e) => e.isNotEmpty).lastOrNull ?? s;
    AppSettings.addRecent(s, title);
    await playItems(context, [VideoItem(title: title, path: s)], 0);
    if (mounted) setState(() => recent = AppSettings.recent);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Network stream', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Play a link: mp4, mkv, m3u8 (HLS), DASH, rtsp, rtmp, http(s)',
            style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 16),
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: _play,
          decoration: InputDecoration(
            hintText: 'https://...',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => _play(url.text),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: Text('Recent', style: TextStyle(fontWeight: FontWeight.w700))),
              TextButton(
                onPressed: () {
                  AppSettings.clearRecent();
                  setState(() => recent = []);
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          for (final r in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(r.source, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _play(r.source),
            ),
        ],
      ],
    );
  }
}

// ---------------- update dialog ----------------
void showUpdateDialog(BuildContext context, UpdateInfo info) {
  final progress = ValueNotifier<double?>(null);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('Update ${info.version} available'),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (_, p, __) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.notes.trim().isEmpty ? 'A new version of Dew Player is ready.' : info.notes.trim(),
                maxLines: 8, overflow: TextOverflow.ellipsis),
            if (p != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: p),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
        FilledButton(
          onPressed: () async {
            progress.value = 0;
            try {
              await UpdateService.downloadAndInstall(info, (v) => progress.value = v);
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Update failed: $e')));
              }
            }
            if (ctx.mounted && !Platform.isWindows) Navigator.pop(ctx);
          },
          child: const Text('Update'),
        ),
      ],
    ),
  );
}
