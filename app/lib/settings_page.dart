import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_settings.dart';
import 'home_page.dart';
import 'languages.dart';
import 'theme.dart';
import 'update_service.dart';

/// Searchable language picker. Returns the language code.
Future<String?> pickLanguage(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(builder: (ctx, setS) {
        final entries = languages.entries
            .where((e) => e.value.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search language',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setS(() => query = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(entries[i].value),
                      trailing: entries[i].key == current
                          ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, entries[i].key),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      });
    },
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => version = p.version);
    });
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final accentList = accents.entries.toList();
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ),
        _section('Appearance'),
        ListTile(
          title: const Text('Theme'),
          trailing: DropdownButton<int>(
            value: AppSettings.themeMode,
            underline: const SizedBox.shrink(),
            items: [
              for (var i = 0; i < themeNames.length; i++)
                DropdownMenuItem(value: i, child: Text(themeNames[i])),
            ],
            onChanged: (v) {
              AppSettings.themeMode = v!;
              themeChanged();
              setState(() {});
            },
          ),
        ),
        ListTile(
          title: const Text('Accent color'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 12,
              children: [
                for (var i = 0; i < accentList.length; i++)
                  GestureDetector(
                    onTap: () {
                      AppSettings.accent = i;
                      themeChanged();
                      setState(() {});
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: accentList[i].value,
                      child: AppSettings.accent == i
                          ? const Icon(Icons.check_rounded, size: 18, color: Colors.black)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        _section('Subtitles'),
        SwitchListTile(
          title: const Text('Auto subtitles (AI)'),
          subtitle: const Text('Create subtitles automatically when a video has none, in any language'),
          value: AppSettings.autoSubs,
          onChanged: (v) => setState(() => AppSettings.autoSubs = v),
        ),
        ListTile(
          title: const Text('AI quality'),
          subtitle: const Text('Better quality needs a bigger one-time download and more power'),
          trailing: DropdownButton<String>(
            value: AppSettings.aiModel,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'tiny', child: Text('Fast (75 MB)')),
              DropdownMenuItem(value: 'base', child: Text('Balanced (142 MB)')),
              DropdownMenuItem(value: 'small', child: Text('Best (466 MB)')),
            ],
            onChanged: (v) => setState(() => AppSettings.aiModel = v!),
          ),
        ),
        SwitchListTile(
          title: const Text('Translate subtitles'),
          subtitle: const Text('Needs internet'),
          value: AppSettings.translateSubs,
          onChanged: (v) => setState(() => AppSettings.translateSubs = v),
        ),
        ListTile(
          title: const Text('Subtitle language'),
          subtitle: Text(languageName(AppSettings.targetLang)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final c = await pickLanguage(context, AppSettings.targetLang);
            if (c != null) setState(() => AppSettings.targetLang = c);
          },
        ),
        ListTile(
          title: const Text('Show'),
          trailing: DropdownButton<SubMode>(
            value: AppSettings.subMode,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: SubMode.translated, child: Text('Translated only')),
              DropdownMenuItem(value: SubMode.both, child: Text('Both lines')),
              DropdownMenuItem(value: SubMode.original, child: Text('Original only')),
            ],
            onChanged: (v) => setState(() => AppSettings.subMode = v!),
          ),
        ),
        ListTile(
          title: const Text('Subtitle size'),
          subtitle: Slider(
            min: 12,
            max: 36,
            divisions: 24,
            label: AppSettings.subSize.round().toString(),
            value: AppSettings.subSize,
            onChanged: (v) => setState(() => AppSettings.subSize = v),
          ),
        ),
        _section('Updates'),
        SwitchListTile(
          title: const Text('Auto update'),
          subtitle: const Text('Check for new versions when the app opens'),
          value: AppSettings.autoUpdate,
          onChanged: (v) => setState(() => AppSettings.autoUpdate = v),
        ),
        ListTile(
          title: const Text('Check for updates'),
          subtitle: Text('Version $version'),
          trailing: const Icon(Icons.system_update_rounded),
          onTap: () async {
            final info = await UpdateService.check();
            if (!context.mounted) return;
            if (info == null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('You are on the latest version')));
            } else {
              showUpdateDialog(context, info);
            }
          },
        ),
        _section('About'),
        const ListTile(
          title: Text('Dew Player'),
          subtitle: Text('Open source (GPL-3.0). github.com/nurulislamtask/Dew-Player'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
