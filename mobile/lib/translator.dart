import 'dart:convert';
import 'package:http/http.dart' as http;

/// Free Google web translate endpoint (same idea as LLPlayer's GoogleV1 engine).
class Translator {
  static final Map<String, String> _cache = {};

  static Future<String?> translate(String text, String to) async {
    final t = text.trim();
    if (t.isEmpty) return '';
    final key = '$to|$t';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
        'client': 'gtx',
        'sl': 'auto',
        'tl': to,
        'dt': 't',
        'q': t,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final sb = StringBuffer();
      for (final part in (j[0] as List)) {
        sb.write(part[0] ?? '');
      }
      final res = sb.toString().trim();
      if (_cache.length > 3000) _cache.clear();
      _cache[key] = res;
      return res;
    } catch (_) {
      return null;
    }
  }
}
