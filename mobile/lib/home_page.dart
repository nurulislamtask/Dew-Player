import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'player_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'update_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<RecentItem> recent = AppSettings.recent;

  @override
  void initState() {
    super.initState();
    if (AppSettings.autoUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate(silent: true));
    }
  }

  Future<void> _checkUpdate({required bool silent}) async {
    final info = await UpdateService.check();
    if (!mounted) return;
    if (info == null) {
      if (!silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('You are on the latest version')));
      }
      return;
    }
    showUpdateDialog(context, info);
  }

  Future<void> _openFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = res?.files.single.path;
    if (path == null) return;
    await _play(path, res!.files.single.name);
  }

  Future<void> _openUrl() async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open network stream'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://... (mp4, mkv, m3u8)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Play')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _play(url, url.split('/').last);
  }

  Future<void> _play(String source, String title) async {
    AppSettings.addRecent(source, title);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerPage(source: source, title: title)),
    );
    if (mounted) setState(() => recent = AppSettings.recent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dew Player', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const SettingsPage()));
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  icon: Icons.video_library_rounded,
                  label: 'Open video',
                  color: dewTeal,
                  onTap: _openFile,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigButton(
                  icon: Icons.link_rounded,
                  label: 'Open URL',
                  color: dewSky,
                  onTap: _openUrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('Recent', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (recent.isNotEmpty)
                TextButton(
                  onPressed: () {
                    AppSettings.clearRecent();
                    setState(() => recent = []);
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('Nothing played yet', style: TextStyle(color: Colors.white38)),
              ),
            ),
          for (final r in recent)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: const Icon(Icons.play_circle_fill_rounded, color: dewTeal),
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(r.source, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _play(r.source, r.title),
              ),
            ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _BigButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Column(
            children: [
              Icon(icon, size: 34, color: color),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog(
    context: context,
    builder: (ctx) {
      double? progress;
      return StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: Text('Update ${info.version} available'),
          content: progress == null
              ? const Text('Download and install the new version now?')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text('${((progress ?? 0) * 100).toStringAsFixed(0)}%'),
                  ],
                ),
          actions: [
            if (progress == null)
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
            if (progress == null)
              FilledButton(
                onPressed: () async {
                  setS(() => progress = 0);
                  try {
                    await UpdateService.downloadAndInstall(info, (p) => setS(() => progress = p));
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx)
                          .showSnackBar(SnackBar(content: Text('Update failed: $e')));
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Update'),
              ),
          ],
        );
      });
    },
  );
}
