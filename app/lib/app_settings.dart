import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RecentItem {
  final String source;
  final String title;
  RecentItem(this.source, this.title);
  Map<String, String> toJson() => {'s': source, 't': title};
}

/// How subtitles are shown on the video.
enum SubMode { translated, both, original }

class AppSettings {
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  // ---- subtitles
  static String get targetLang => _p.getString('targetLang') ?? 'bn';
  static set targetLang(String v) => _p.setString('targetLang', v);

  /// Create subtitles with AI automatically when the video has none.
  static bool get autoSubs => _p.getBool('autoSubs') ?? true;
  static set autoSubs(bool v) => _p.setBool('autoSubs', v);

  static bool get translateSubs => _p.getBool('translateSubs') ?? true;
  static set translateSubs(bool v) => _p.setBool('translateSubs', v);

  static SubMode get subMode {
    final i = _p.getInt('subMode') ?? 0;
    return SubMode.values[i.clamp(0, SubMode.values.length - 1)];
  }

  static set subMode(SubMode v) => _p.setInt('subMode', v.index);

  static String get aiModel => _p.getString('aiModel') ?? 'base';
  static set aiModel(String v) => _p.setString('aiModel', v);

  static double get subSize => _p.getDouble('subSize') ?? 18;
  static set subSize(double v) => _p.setDouble('subSize', v);

  // ---- look
  /// 0 system, 1 dark, 2 light, 3 amoled black
  static int get themeMode => _p.getInt('themeMode') ?? 1;
  static set themeMode(int v) => _p.setInt('themeMode', v);

  static int get accent => _p.getInt('accent') ?? 0;
  static set accent(int v) => _p.setInt('accent', v);

  // ---- updates
  static bool get autoUpdate => _p.getBool('autoUpdate') ?? true;
  static set autoUpdate(bool v) => _p.setBool('autoUpdate', v);

  // ---- resume positions
  static Duration? resumeFor(String source) {
    final ms = _p.getInt('pos:${source.hashCode}');
    return ms == null ? null : Duration(milliseconds: ms);
  }

  static void saveResume(String source, Duration pos, Duration total) {
    final key = 'pos:${source.hashCode}';
    if (total > Duration.zero &&
        (pos < const Duration(seconds: 8) || pos > total - const Duration(seconds: 10))) {
      _p.remove(key);
    } else {
      _p.setInt(key, pos.inMilliseconds);
    }
  }

  // ---- recent network streams / files
  static List<RecentItem> get recent {
    final raw = _p.getString('recent');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RecentItem(e['s'] as String, e['t'] as String))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void addRecent(String source, String title) {
    final list = recent.where((e) => e.source != source).toList();
    list.insert(0, RecentItem(source, title));
    if (list.length > 20) list.removeRange(20, list.length);
    _p.setString('recent', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static void clearRecent() => _p.remove('recent');
}
