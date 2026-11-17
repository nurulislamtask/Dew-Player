import 'package:flutter/material.dart';
import 'app_settings.dart';

const accents = <String, Color>{
  'Teal': Color(0xFF2DD4BF),
  'Sky': Color(0xFF38BDF8),
  'Violet': Color(0xFF8B5CF6),
  'Rose': Color(0xFFF43F5E),
  'Orange': Color(0xFFFB923C),
  'Green': Color(0xFF4ADE80),
};

const themeNames = ['System', 'Dark', 'Light', 'Black (AMOLED)'];

/// Rebuilds the whole app when the look changes.
final themeRevision = ValueNotifier<int>(0);
void themeChanged() => themeRevision.value++;

Color accentColor() {
  final list = accents.values.toList();
  return list[AppSettings.accent.clamp(0, list.length - 1)];
}

ThemeData buildTheme(Brightness brightness, {bool amoled = false}) {
  final accent = accentColor();
  var scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  scheme = scheme.copyWith(primary: accent);
  if (brightness == Brightness.dark) {
    scheme = scheme.copyWith(
      surface: amoled ? Colors.black : const Color(0xFF111827),
      onPrimary: Colors.black,
    );
  }
  final bg = brightness == Brightness.dark
      ? (amoled ? Colors.black : const Color(0xFF0B1220))
      : const Color(0xFFF6F8FB);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(backgroundColor: bg, elevation: 0, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: bg, elevation: 0),
    sliderTheme: const SliderThemeData(trackHeight: 3),
    dividerTheme: const DividerThemeData(space: 1),
  );
}

ThemeMode flutterThemeMode() {
  switch (AppSettings.themeMode) {
    case 1:
    case 3:
      return ThemeMode.dark;
    case 2:
      return ThemeMode.light;
    default:
      return ThemeMode.system;
  }
}
