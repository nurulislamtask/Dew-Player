import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'subtitles.dart';

/// Offline AI subtitles (Whisper, whisper.cpp on the phone).
///
/// How it works (light on memory):
///  1. a hidden mpv instance decodes only the audio to a 16 kHz mono WAV file
///  2. the audio is cut into 30 s chunks, each chunk is transcribed by Whisper
///  3. every finished chunk is delivered immediately, so subtitles appear while it works
/// The Whisper model (tiny ~75 MB, base ~142 MB, small ~466 MB) is downloaded once, on first use.
class AiSubtitleGenerator {
  static const _bytesPerSec = 16000 * 2; // 16 kHz, mono, 16 bit
  static const _chunkSec = 30;
  static const _modelHost = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  bool _cancelled = false;
  bool get running => _running;
  bool _running = false;
  Player? _extractor;

  void cancel() => _cancelled = true;

  /// [model] is one of: 'tiny', 'base', 'small'.
  Future<void> start({
    required String source,
    required Duration from,
    required String model,
    required void Function(List<SubLine> lines) onLines,
    required void Function(String status) onStatus,
  }) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    final dir = await getTemporaryDirectory();
    final wavPath = '${dir.path}/dew_ai_audio.wav';
    final chunkPath = '${dir.path}/dew_ai_chunk.wav';
    for (final p in [wavPath, chunkPath]) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }

    RandomAccessFile? raf;
    var extractionDone = false;
    try {
      // ---- 1) audio extraction in a hidden player
      onStatus('Preparing audio...');
      final ex = Player();
      _extractor = ex;
      final np = ex.platform as NativePlayer;
      await np.setProperty('vo', 'null');
      await np.setProperty('vid', 'no');
      await np.setProperty('sid', 'no');
      await np.setProperty('ao', 'pcm');
      await np.setProperty('ao-pcm-file', wavPath);
      await np.setProperty('ao-pcm-waveheader', 'yes');
      await np.setProperty('audio-samplerate', '16000');
      await np.setProperty('audio-channels', 'mono');
      await np.setProperty('audio-format', 's16');
      if (from.inSeconds > 0) {
        await np.setProperty('start', from.inSeconds.toString());
      }
      ex.stream.completed.listen((c) {
        if (c) extractionDone = true;
      });
      await ex.open(Media(source), play: true);

      // wait for the file to appear
      final waitStart = DateTime.now();
      while (!await File(wavPath).exists()) {
        if (_cancelled) return;
        if (DateTime.now().difference(waitStart).inSeconds > 25) {
          throw 'Audio extraction is not available for this video';
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
      raf = await File(wavPath).open();

      // ---- 2) Whisper
      onStatus('Preparing AI (first time downloads the model)...');
      Whisper? whisper;
      String? winExe;
      String? winModel;
      if (Platform.isWindows) {
        winExe = _windowsExe();
        if (winExe == null) throw 'AI engine is not included in this build';
        winModel = await _windowsModel(model, onStatus);
      } else {
        whisper = Whisper(
          model: _modelOf(model),
          downloadHost: _modelHost,
        );
      }

      var offset = 44; // skip WAV header (size fields are not final while writing)
      var chunkStart = from;
      var emptyStreak = 0;

      while (!_cancelled) {
        final want = _chunkSec * _bytesPerSec;
        var size = await raf.length();
        while (size < offset + want && !extractionDone && !_cancelled) {
          await Future.delayed(const Duration(milliseconds: 400));
          size = await raf.length();
        }
        if (_cancelled) break;
        size = await raf.length();
        final avail = size - offset;
        if (avail < _bytesPerSec && extractionDone) break; // finished
        if (avail < _bytesPerSec) continue;
        var take = avail < want ? avail : want;
        take -= take % 2;

        await raf.setPosition(offset);
        final pcm = await raf.read(take);
        await File(chunkPath).writeAsBytes(_wav(pcm), flush: true);

        onStatus('Transcribing ${_fmt(chunkStart)} ...');
        final lines = Platform.isWindows
            ? await _transcribeWindows(winExe!, winModel!, chunkPath, chunkStart)
            : await _transcribe(whisper!, chunkPath, chunkStart);
        if (_cancelled) break;
        if (lines.isNotEmpty) {
          emptyStreak = 0;
          onLines(lines);
        } else {
          emptyStreak++;
        }

        offset += take;
        chunkStart += Duration(milliseconds: (take * 1000 ~/ _bytesPerSec));
      }
      onStatus(_cancelled ? 'AI subtitles stopped' : 'AI subtitles finished');
      if (emptyStreak > 0 && !_cancelled) {
        // nothing special, just silence at the end
      }
    } catch (e) {
      onStatus('AI subtitles failed: $e');
    } finally {
      _running = false;
      try {
        await raf?.close();
      } catch (_) {}
      try {
        await _extractor?.dispose();
      } catch (_) {}
      _extractor = null;
      for (final p in [wavPath, chunkPath]) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  // ---- Windows: whisper.cpp command line tool shipped next to the app
  String? _windowsExe() {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final exe = File('$dir\\whisper\\whisper-cli.exe');
    return exe.existsSync() ? exe.path : null;
  }

  Future<String> _windowsModel(String model, void Function(String) onStatus) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}\\models');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}\\ggml-$model.bin');
    if (await file.exists() && await file.length() > 1000000) return file.path;
    final tmp = File('${file.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse('$_modelHost/ggml-$model.bin')));
      if (res.statusCode != 200) throw 'Model download failed (${res.statusCode})';
      final total = res.contentLength ?? 0;
      var got = 0;
      var lastPct = -1;
      final sink = tmp.openWrite();
      await for (final c in res.stream) {
        if (_cancelled) break;
        sink.add(c);
        got += c.length;
        if (total > 0) {
          final pct = got * 100 ~/ total;
          if (pct != lastPct) {
            lastPct = pct;
            onStatus('Downloading AI model $pct%');
          }
        }
      }
      await sink.close();
      if (_cancelled) throw 'stopped';
      await tmp.rename(file.path);
    } finally {
      client.close();
    }
    return file.path;
  }

  Future<List<SubLine>> _transcribeWindows(
      String exe, String model, String wav, Duration shift) async {
    final base = wav.substring(0, wav.length - 4);
    final r = await Process.run(exe, ['-m', model, '-f', wav, '-l', 'auto', '-osrt', '-of', base, '-np']);
    if (r.exitCode != 0) throw 'AI engine error ${r.exitCode}';
    final srt = File('$base.srt');
    if (!await srt.exists()) return [];
    final text = utf8.decode(await srt.readAsBytes(), allowMalformed: true);
    await srt.delete();
    final out = <SubLine>[];
    for (final l in parseSubtitles(text, 'srt')) {
      final t = l.text.trim();
      if (t.isEmpty || RegExp(r'^[\[\(].*[\]\)]$').hasMatch(t)) continue;
      out.add(SubLine(shift + l.start, shift + l.end, t));
    }
    return out;
  }

  WhisperModel _modelOf(String m) {
    switch (m) {
      case 'small':
        return WhisperModel.small;
      case 'base':
        return WhisperModel.base;
      default:
        return WhisperModel.tiny;
    }
  }

  Future<List<SubLine>> _transcribe(Whisper whisper, String path, Duration shift) async {
    final out = <SubLine>[];
    final dynamic res = await whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: path,
        isTranslate: false,
        isNoTimestamps: false,
        splitOnWord: false,
      ),
    );
    final dynamic segs = res.segments;
    if (segs is! List) return out;
    for (final dynamic s in segs) {
      final String text = (s.text as String).trim();
      if (text.isEmpty) continue;
      // skip pure sound tags like [MUSIC] or (applause)
      if (RegExp(r'^[\[\(].*[\]\)]$').hasMatch(text)) continue;
      final Duration a = s.fromTs as Duration;
      final Duration b = s.toTs as Duration;
      out.add(SubLine(shift + a, shift + b, text));
    }
    return out;
  }

  Uint8List _wav(Uint8List pcm) {
    final n = pcm.length;
    final b = BytesBuilder();
    void s(String t) => b.add(t.codeUnits);
    void i32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void i16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
    s('RIFF');
    i32(36 + n);
    s('WAVE');
    s('fmt ');
    i32(16);
    i16(1); // PCM
    i16(1); // mono
    i32(16000);
    i32(16000 * 2);
    i16(2);
    i16(16);
    s('data');
    i32(n);
    b.add(pcm);
    return b.toBytes();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
  }
}
