import 'dart:io';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';

/// One video the user can play.
class VideoItem {
  final String title;
  final Duration? duration;
  final AssetEntity? asset; // Android library entry
  String? path; // resolved file path / URL

  VideoItem({required this.title, this.duration, this.asset, this.path});

  Future<String?> resolve() async {
    if (path != null) return path;
    final f = await asset?.file;
    path = f?.path;
    return path;
  }

  Future<Uint8List?> thumbnail() async {
    final a = asset;
    if (a == null) return null;
    return a.thumbnailDataWithSize(const ThumbnailSize(240, 160));
  }
}

class VideoFolder {
  final String name;
  final List<VideoItem> videos;
  VideoFolder(this.name, this.videos);
}

const videoExtensions = {
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg',
  'ts', 'm2ts', 'mts', '3gp', '3g2', 'ogv', 'vob', 'divx', 'asf', 'rm', 'rmvb',
};

bool isVideoPath(String p) {
  final i = p.lastIndexOf('.');
  return i >= 0 && videoExtensions.contains(p.substring(i + 1).toLowerCase());
}

String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

class LibraryResult {
  final List<VideoFolder> folders;
  final bool denied;
  LibraryResult(this.folders, {this.denied = false});
}

/// Finds videos on the device (like MX Player's folder list).
class VideoLibrary {
  static Future<LibraryResult> load() async {
    if (Platform.isAndroid) return _loadAndroid();
    if (Platform.isWindows) return _loadWindows();
    return LibraryResult([]);
  }

  static Future<LibraryResult> _loadAndroid() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess) return LibraryResult([], denied: true);
    final paths = await PhotoManager.getAssetPathList(type: RequestType.video, onlyAll: false);
    final folders = <VideoFolder>[];
    for (final p in paths) {
      final count = await p.assetCountAsync;
      if (count == 0) continue;
      final assets = await p.getAssetListPaged(page: 0, size: count);
      final items = <VideoItem>[
        for (final a in assets)
          VideoItem(
            title: a.title ?? 'Video',
            duration: a.videoDuration,
            asset: a,
          ),
      ];
      if (items.isNotEmpty) folders.add(VideoFolder(p.name, items));
    }
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return LibraryResult(folders);
  }

  static Future<LibraryResult> _loadWindows() async {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return LibraryResult([]);
    final roots = ['Videos', 'Downloads', 'Desktop']
        .map((d) => Directory('$home\\$d'))
        .where((d) => d.existsSync());
    final byFolder = <String, List<VideoItem>>{};
    for (final root in roots) {
      try {
        await for (final e in root.list(recursive: true, followLinks: false)
            .handleError((_) {}, test: (_) => true)) {
          if (e is! File || !isVideoPath(e.path)) continue;
          final sep = e.path.lastIndexOf('\\');
          final dir = e.path.substring(0, sep);
          final name = dir.substring(dir.lastIndexOf('\\') + 1);
          byFolder
              .putIfAbsent(name, () => [])
              .add(VideoItem(title: fileNameOf(e.path), path: e.path));
        }
      } catch (_) {}
    }
    final folders = [for (final e in byFolder.entries) VideoFolder(e.key, e.value)];
    for (final f in folders) {
      f.videos.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return LibraryResult(folders);
  }
}
