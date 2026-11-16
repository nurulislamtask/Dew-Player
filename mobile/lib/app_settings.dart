import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RecentItem {
  final String source;
  final String title;
  RecentItem(this.source, this.title);
  Map<String, String> toJson() => {'s': source, 't': title};
}

class AppSettings {
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static String get targetLang => _p.getString('targetLang') ?? 'bn';
  static set targetLang(String v) => _p.setString('targetLang', v);

  static bool get autoUpdate => _p.getBool('autoUpdate') ?? true;
  static set autoUpdate(bool v) => _p.setBool('autoUpdate', v);

  static bool get translateByDefault => _p.getBool('translateByDefault') ?? true;
  static set translateByDefault(bool v) => _p.setBool('translateByDefault', v);

  static double get subSize => _p.getDouble('subSize') ?? 18;
  static set subSize(double v) => _p.setDouble('subSize', v);

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

const languages = <String, String>{
  'bn': 'Bangla',
  'en': 'English',
  'hi': 'Hindi',
  'ur': 'Urdu',
  'ar': 'Arabic',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh-CN': 'Chinese',
  'ru': 'Russian',
  'pt': 'Portuguese',
  'tr': 'Turkish',
  'id': 'Indonesian',
};
