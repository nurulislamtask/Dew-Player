import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String url;
  final String notes;
  final String fileName;
  UpdateInfo(this.version, this.url, this.notes, this.fileName);
}

/// Auto update through GitHub Releases (APK on Android, Setup.exe on Windows).
class UpdateService {
  static const repo = 'nurulislamtask/Dew-Player';

  static bool _isNewer(String a, String b) {
    List<int> p(String v) =>
        v.split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0;
      final yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  /// Returns null when up to date or when the check failed.
  static Future<UpdateInfo?> check() async {
    try {
      final r = await http
          .get(
            Uri.https('api.github.com', '/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final ver = (j['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
      final current = (await PackageInfo.fromPlatform()).version;
      if (!_isNewer(ver, current)) return null;

      final assets = (j['assets'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic>? pick;
      if (Platform.isWindows) {
        for (final a in assets) {
          if ((a['name'] as String).toLowerCase().endsWith('setup.exe')) pick = a;
        }
      } else if (Platform.isAndroid) {
        final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
        final wantArm64 = abis.contains('arm64-v8a');
        for (final a in assets) {
          final n = (a['name'] as String).toLowerCase();
          if (!n.endsWith('.apk')) continue;
          if (wantArm64 ? n.contains('arm64') : n.contains('armv7')) {
            pick = a;
            break;
          }
        }
        pick ??= assets.cast<Map<String, dynamic>?>().firstWhere(
              (a) => (a!['name'] as String).toLowerCase().endsWith('.apk'),
              orElse: () => null,
            );
      }
      if (pick == null) return null;
      return UpdateInfo(ver, pick['browser_download_url'] as String,
          (j['body'] as String?) ?? '', pick['name'] as String);
    } catch (_) {
      return null;
    }
  }

  static Future<void> downloadAndInstall(
      UpdateInfo info, void Function(double) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${info.fileName}');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(info.url)));
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    if (Platform.isWindows) {
      // the Velopack installer updates the app in place, then starts it again
      await Process.start(file.path, [], mode: ProcessStartMode.detached);
      exit(0);
    } else {
      await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    }
  }
}
