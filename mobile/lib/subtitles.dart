import 'dart:convert';
import 'dart:io';

class SubLine {
  final Duration start;
  final Duration end;
  final String text;
  const SubLine(this.start, this.end, this.text);
}

final _time = RegExp(r'(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})');

Duration? _parseTime(String s) {
  final m = _time.firstMatch(s.trim());
  if (m == null) return null;
  final h = int.tryParse(m.group(1) ?? '0') ?? 0;
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  var msStr = m.group(4)!;
  msStr = msStr.padRight(3, '0');
  final ms = int.parse(msStr.substring(0, 3));
  return Duration(hours: h, minutes: min, seconds: sec, milliseconds: ms);
}

String _clean(String t) {
  return t
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\n', '\n')
      .trim();
}

Future<List<SubLine>> loadSubtitleFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final content = utf8.decode(bytes, allowMalformed: true);
  final ext = path.toLowerCase().split('.').last;
  return parseSubtitles(content, ext);
}

List<SubLine> parseSubtitles(String content, String ext) {
  content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (content.startsWith('﻿')) content = content.substring(1);
  final lines = (ext == 'ass' || ext == 'ssa')
      ? _parseAss(content)
      : _parseSrtVtt(content);
  lines.sort((a, b) => a.start.compareTo(b.start));
  return lines;
}

List<SubLine> _parseSrtVtt(String content) {
  final out = <SubLine>[];
  final blocks = content.split(RegExp(r'\n\s*\n'));
  for (final b in blocks) {
    final ls = b.split('\n');
    final i = ls.indexWhere((l) => l.contains('-->'));
    if (i < 0) continue;
    final parts = ls[i].split('-->');
    if (parts.length < 2) continue;
    final s = _parseTime(parts[0]);
    final e = _parseTime(parts[1].trim().split(' ').first);
    if (s == null || e == null) continue;
    final text = _clean(ls.sublist(i + 1).join('\n'));
    if (text.isEmpty) continue;
    out.add(SubLine(s, e, text));
  }
  return out;
}

List<SubLine> _parseAss(String content) {
  final out = <SubLine>[];
  for (final l in content.split('\n')) {
    if (!l.startsWith('Dialogue:')) continue;
    final f = l.substring(9).split(',');
    if (f.length < 10) continue;
    final s = _parseTime(f[1]);
    final e = _parseTime(f[2]);
    if (s == null || e == null) continue;
    final text = _clean(f.sublist(9).join(','));
    if (text.isEmpty) continue;
    out.add(SubLine(s, e, text));
  }
  return out;
}

/// Text of the line shown at [pos], or '' (binary search).
String lineAt(List<SubLine> list, Duration pos) {
  final i = indexAt(list, pos);
  return i < 0 ? '' : list[i].text;
}

int indexAt(List<SubLine> list, Duration pos) {
  var lo = 0, hi = list.length - 1, found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].start <= pos) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  // look back a few lines for overlapping cues
  for (var k = found; k >= 0 && k > found - 3; k--) {
    if (pos <= list[k].end) return k;
  }
  return -1;
}
