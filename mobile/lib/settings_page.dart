import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_settings.dart';
import 'home_page.dart';
import 'update_service.dart';

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
    PackageInfo.fromPlatform().then((p) => setState(() => version = p.version));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Translate to'),
            subtitle: Text(languages[AppSettings.targetLang] ?? AppSettings.targetLang),
            trailing: DropdownButton<String>(
              value: languages.containsKey(AppSettings.targetLang) ? AppSettings.targetLang : 'en',
              underline: const SizedBox.shrink(),
              items: [
                for (final e in languages.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => AppSettings.targetLang = v!),
            ),
          ),
          SwitchListTile(
            title: const Text('Auto translate subtitles'),
            subtitle: const Text('Show a translated second subtitle line'),
            value: AppSettings.translateByDefault,
            onChanged: (v) => setState(() => AppSettings.translateByDefault = v),
          ),
          ListTile(
            title: const Text('Subtitle size'),
            subtitle: Slider(
              min: 12,
              max: 34,
              divisions: 22,
              label: AppSettings.subSize.round().toString(),
              value: AppSettings.subSize,
              onChanged: (v) => setState(() => AppSettings.subSize = v),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Auto update'),
            subtitle: const Text('Check GitHub for new versions when the app opens'),
            value: AppSettings.autoUpdate,
            onChanged: (v) => setState(() => AppSettings.autoUpdate = v),
          ),
          ListTile(
            title: const Text('Check for updates'),
            subtitle: Text('Current version: $version'),
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
          const Divider(),
          const ListTile(
            title: Text('About'),
            subtitle: Text(
                'Dew Player is open source (GPL-3.0) and inspired by LLPlayer by umlx5h.\n'
                'github.com/nurulislamtask/Dew-Player'),
          ),
        ],
      ),
    );
  }
}
