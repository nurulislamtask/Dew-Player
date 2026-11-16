import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// OCR for subtitles that are pictures (PGS/VobSub) or burned into the video.
/// Every ~0.8 s the bottom part of the current frame is read with Google ML Kit (on-device, offline).
class OcrService {
  Timer? _timer;
  bool _busy = false;
  TextRecognizer? _recognizer;
  String _last = '';

  bool get running => _timer != null;

  static const scripts = <String, TextRecognitionScript>{
    'Latin (English, Spanish, ...)': TextRecognitionScript.latin,
    'Chinese': TextRecognitionScript.chinese,
    'Japanese': TextRecognitionScript.japanese,
    'Korean': TextRecognitionScript.korean,
    'Devanagari (Hindi, ...)': TextRecognitionScript.devanagiri,
  };

  void start(Player player, TextRecognitionScript script, void Function(String text) onText) {
    stop();
    _recognizer = TextRecognizer(script: script);
    _last = '';
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (_busy) return;
      _busy = true;
      try {
        final text = await _readFrame(player);
        if (text != null && text != _last) {
          _last = text;
          onText(text);
        }
      } catch (_) {
      } finally {
        _busy = false;
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _recognizer?.close();
    _recognizer = null;
  }

  Future<String?> _readFrame(Player player) async {
    final bytes = await player.screenshot(format: 'image/jpeg', includeLibassSubtitles: true);
    if (bytes == null) return null;

    // crop the bottom 35 % (where subtitles are)
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final h = (img.height * 0.35).round();
    final w = img.width;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, (img.height - h).toDouble(), w.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint(),
    );
    final cropped = await rec.endRecording().toImage(w, h);
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    cropped.dispose();
    if (data == null) return null;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dew_ocr.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    final res = await _recognizer?.processImage(InputImage.fromFilePath(file.path));
    final text = (res?.text ?? '').replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    return text;
  }
}
