import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'app_settings.dart';
import 'home_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) await windowManager.ensureInitialized();
  await AppSettings.init();
  // picked files are copied into the cache by the system picker: clean old copies
  try {
    await FilePicker.platform.clearTemporaryFiles();
  } catch (_) {}
  runApp(const DewApp());
}

class DewApp extends StatelessWidget {
  const DewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeRevision,
      builder: (_, __, ___) => MaterialApp(
        title: 'Dew Player',
        debugShowCheckedModeBanner: false,
        themeMode: flutterThemeMode(),
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark, amoled: AppSettings.themeMode == 3),
        home: const HomePage(),
      ),
    );
  }
}
