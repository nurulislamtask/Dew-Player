import 'package:flutter/material.dart';

const dewTeal = Color(0xFF2DD4BF);
const dewSky = Color(0xFF38BDF8);
const dewBg = Color(0xFF0B1220);

ThemeData dewTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: dewTeal,
    brightness: Brightness.dark,
  ).copyWith(primary: dewTeal, secondary: dewSky, surface: const Color(0xFF111A2E));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dewBg,
    appBarTheme: const AppBarTheme(backgroundColor: dewBg, elevation: 0),
    sliderTheme: const SliderThemeData(trackHeight: 3),
  );
}
