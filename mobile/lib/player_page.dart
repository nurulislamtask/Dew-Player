import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'app_settings.dart';
import 'subtitles.dart';
import 'theme.dart';
import 'translator.dart';

class PlayerPage extends StatefulWidget {
  final String source;
  final String title;
  const PlayerPage({super.key, required this.source, required this.title});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  final subs = <StreamSubscription>[];

  final pos = ValueNotifier<Duration>(Duration.zero);
  final dragValue = ValueNotifier<double?>(null);
  final primaryText = ValueNotifier<String>('');
  final secondaryText = ValueNotifier<String>('');
  final hint = ValueNotifier<String>('');

  Duration duration = Duration.zero;
  bool playing = true;
  bool buffering = false;
  bool showControls = true;
  double rate = 1.0;
  double volume = 100;
  Timer? hideTimer;
  Timer? hintTimer;

  List<SubLine> primaryExt = [];
  List<SubLine> secondaryExt = [];
  String embeddedText = '';
  bool translate = AppSettings.translateByDefault;
  int _reqId = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    subs.add(player.stream.position.listen((d) {
      pos.value = d;
      _tick(d);
    }));
    subs.add(player.stream.duration.listen((d) => setState(() => duration = d)));
    subs.add(player.stream.playing.listen((p) {
      setState(() => playing = p);
      _scheduleHide();
    }));
    subs.add(player.stream.buffering.listen((b) => setState(() => buffering = b)));
    subs.add(player.stream.subtitle.listen((l) {
      embeddedText = l.where((e) => e.trim().isNotEmpty).join('\n');
      _tick(pos.value);
    }));
    subs.add(player.stream.tracks.listen((_) {
      if (mounted) setState(() {});
    }));

    player.open(Media(widget.source));
    _scheduleHide();
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    hintTimer?.cancel();
    for (final s in subs) {
      s.cancel();
    }
    player.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---------- subtitles ----------
  void _tick(Duration d) {
    final p = primaryExt.isNotEmpty ? lineAt(primaryExt, d) : embeddedText;
    if (p != primaryText.value) {
      primaryText.value = p;
      _updateSecondary(p);
    }
    if (secondaryExt.isNotEmpty) {
      final s = lineAt(secondaryExt, d);
      if (s != secondaryText.value) secondaryText.value = s;
    }
  }

  Future<void> _updateSecondary(String p) async {
    if (secondaryExt.isNotEmpty) return;
    if (!translate || p.isEmpty) {
      secondaryText.value = '';
      return;
    }
    final id = ++_reqId;
    final t = await Translator.translate(p, AppSettings.targetLang);
    if (mounted && id == _reqId) secondaryText.value = t ?? '';
  }

  Future<List<SubLine>?> _pickSubtitleFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    final path = res?.files.single.path;
    if (path == null) return null;
    try {
      final list = await loadSubtitleFile(path);
      if (list.isEmpty) _toast('No subtitle lines found in this file');
      return list.isEmpty ? null : list;
    } catch (e) {
      _toast('Cannot read subtitle: $e');
      return null;
    }
  }

  // ---------- controls ----------
  void _toast(String text) {
    hint.value = text;
    hintTimer?.cancel();
    hintTimer = Timer(const Duration(milliseconds: 900), () => hint.value = '');
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    if (!playing) return;
    hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => showControls = !showControls);
    if (showControls) _scheduleHide();
  }

  void _seekBy(int seconds) {
    var t = pos.value + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (duration > Duration.zero && t > duration) t = duration;
    player.seek(t);
    _toast(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: controller,
              controls: NoVideoControls,
              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
            ),
            _gestureLayer(),
            _subtitleOverlay(),
            if (buffering)
              const Center(child: CircularProgressIndicator(color: dewTeal)),
            ValueListenableBuilder<String>(
              valueListenable: hint,
              builder: (_, v, __) => v.isEmpty
                  ? const SizedBox.shrink()
                  : Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(v, style: const TextStyle(fontSize: 18)),
                      ),
                    ),
            ),
            AnimatedOpacity(
              opacity: showControls ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(ignoring: !showControls, child: _controls()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gestureLayer() {
    return LayoutBuilder(builder: (context, c) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        onDoubleTapDown: (d) {
          _seekBy(d.localPosition.dx < c.maxWidth / 2 ? -10 : 10);
        },
        onDoubleTap: () {},
        onLongPressStart: (_) {
          player.setRate(2.0);
          _toast('2x');
        },
        onLongPressEnd: (_) => player.setRate(rate),
        onVerticalDragUpdate: (d) {
          if (d.localPosition.dx > c.maxWidth / 2) {
            volume = (volume - d.delta.dy * 0.6).clamp(0, 100);
            player.setVolume(volume);
            _toast('Volume ${volume.round()}%');
          }
        },
      );
    });
  }

  Widget _subtitleOverlay() {
    final size = AppSettings.subSize;
    Widget line(String text, Color color, double fs, {VoidCallback? onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: fs,
              fontWeight: FontWeight.w600,
              height: 1.25,
              shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: 24,
      right: 24,
      bottom: showControls ? 92 : 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: secondaryText,
            builder: (_, s, __) =>
                s.isEmpty ? const SizedBox.shrink() : line(s, dewSky, size - 2),
          ),
          ValueListenableBuilder<String>(
            valueListenable: primaryText,
            builder: (_, p, __) => p.isEmpty
                ? const SizedBox.shrink()
                : line(p, Colors.white, size, onTap: () => _lookup(p)),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Stack(
      children: [
        // top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, left: 4, right: 4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.subtitles_rounded),
                  tooltip: 'Subtitles',
                  onPressed: _subtitleMenu,
                ),
                IconButton(
                  icon: const Icon(Icons.format_list_bulleted_rounded),
                  tooltip: 'Subtitle list',
                  onPressed: _sidebar,
                ),
                IconButton(
                  icon: const Icon(Icons.speed_rounded),
                  tooltip: 'Speed',
                  onPressed: _speedMenu,
                ),
              ],
            ),
          ),
        ),
        // center play button
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.replay_10_rounded),
                onPressed: () => _seekBy(-10),
              ),
              const SizedBox(width: 18),
              IconButton.filled(
                iconSize: 44,
                style: IconButton.styleFrom(
                  backgroundColor: dewTeal.withOpacity(0.9),
                  foregroundColor: Colors.black,
                ),
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: () {
                  player.playOrPause();
                  _scheduleHide();
                },
              ),
              const SizedBox(width: 18),
              IconButton(
                iconSize: 38,
                icon: const Icon(Icons.forward_10_rounded),
                onPressed: () => _seekBy(10),
              ),
            ],
          ),
        ),
        // bottom seek bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.only(
                left: 16, right: 16, bottom: MediaQuery.of(context).padding.bottom + 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: ValueListenableBuilder<Duration>(
              valueListenable: pos,
              builder: (_, p, __) {
                final total = duration.inMilliseconds.toDouble();
                final cur = p.inMilliseconds.toDouble().clamp(0, total > 0 ? total : 1).toDouble();
                return ValueListenableBuilder<double?>(
                  valueListenable: dragValue,
                  builder: (_, drag, __) {
                    final shown = drag ?? cur;
                    return Row(
                      children: [
                        Text(_fmt(Duration(milliseconds: shown.round()))),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: total > 0 ? total : 1,
                            value: shown.clamp(0, total > 0 ? total : 1).toDouble(),
                            onChanged: (v) {
                              dragValue.value = v;
                              hideTimer?.cancel();
                            },
                            onChangeEnd: (v) {
                              player.seek(Duration(milliseconds: v.round()));
                              dragValue.value = null;
                              _scheduleHide();
                            },
                          ),
                        ),
                        Text(_fmt(duration)),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ---------- sheets ----------
  void _speedMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                title: Text('${r}x'),
                trailing: rate == r ? const Icon(Icons.check_rounded, color: dewTeal) : null,
                onTap: () {
                  setState(() => rate = r);
                  player.setRate(r);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _subtitleMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final embedded = player.state.tracks.subtitle
            .where((t) => t.id != 'auto' && t.id != 'no')
            .toList();
        final curId = player.state.track.subtitle.id;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Primary subtitle',
                      style: TextStyle(fontWeight: FontWeight.w700, color: dewTeal)),
                ),
                ListTile(
                  leading: const Icon(Icons.subtitles_off_rounded),
                  title: const Text('Off'),
                  trailing: (primaryExt.isEmpty && curId == 'no')
                      ? const Icon(Icons.check_rounded, color: dewTeal)
                      : null,
                  onTap: () {
                    primaryExt = [];
                    player.setSubtitleTrack(SubtitleTrack.no());
                    embeddedText = '';
                    _tick(pos.value);
                    setS(() {});
                  },
                ),
                for (final t in embedded)
                  ListTile(
                    leading: const Icon(Icons.closed_caption_rounded),
                    title: Text(t.title ?? t.language ?? 'Track ${t.id}'),
                    subtitle: t.language != null ? Text(t.language!) : null,
                    trailing: (primaryExt.isEmpty && curId == t.id)
                        ? const Icon(Icons.check_rounded, color: dewTeal)
                        : null,
                    onTap: () {
                      primaryExt = [];
                      player.setSubtitleTrack(t);
                      setS(() {});
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('Load subtitle file...'),
                  subtitle: primaryExt.isNotEmpty ? const Text('External file loaded') : null,
                  onTap: () async {
                    final l = await _pickSubtitleFile();
                    if (l != null) {
                      primaryExt = l;
                      player.setSubtitleTrack(SubtitleTrack.no());
                      _tick(pos.value);
                      setS(() {});
                    }
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Secondary subtitle',
                      style: TextStyle(fontWeight: FontWeight.w700, color: dewSky)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.translate_rounded),
                  title: Text('Auto translate to ${languages[AppSettings.targetLang] ?? AppSettings.targetLang}'),
                  subtitle: const Text('Needs internet'),
                  value: translate && secondaryExt.isEmpty,
                  onChanged: (v) {
                    translate = v;
                    secondaryExt = [];
                    _updateSecondary(primaryText.value);
                    if (!v) secondaryText.value = '';
                    setS(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('Load second subtitle file...'),
                  subtitle: secondaryExt.isNotEmpty ? const Text('External file loaded') : null,
                  onTap: () async {
                    final l = await _pickSubtitleFile();
                    if (l != null) {
                      secondaryExt = l;
                      secondaryText.value = '';
                      _tick(pos.value);
                      setS(() {});
                    }
                  },
                ),
                if (secondaryExt.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.close_rounded),
                    title: const Text('Remove second subtitle file'),
                    onTap: () {
                      secondaryExt = [];
                      secondaryText.value = '';
                      _updateSecondary(primaryText.value);
                      setS(() {});
                    },
                  ),
                const Divider(),
                ListTile(
                  title: const Text('Subtitle size'),
                  subtitle: Slider(
                    min: 12,
                    max: 34,
                    value: AppSettings.subSize,
                    onChanged: (v) {
                      AppSettings.subSize = v;
                      setS(() {});
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _sidebar() {
    final list = primaryExt.isNotEmpty ? primaryExt : secondaryExt;
    if (list.isEmpty) {
      _toast('Load a subtitle file to use the list');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final cur = indexAt(list, pos.value);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (_, scroll) => ListView.builder(
            controller: scroll,
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              selected: i == cur,
              selectedColor: dewTeal,
              leading: Text(_fmt(list[i].start),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              title: Text(list[i].text),
              onTap: () {
                player.seek(list[i].start);
                Navigator.pop(ctx);
              },
            ),
          ),
        );
      },
    );
  }

  void _lookup(String sentence) {
    final words = sentence
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), ''))
        .where((w) => w.isNotEmpty)
        .toList();
    String? selected;
    String? result;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tap a word to translate',
                    style: TextStyle(fontWeight: FontWeight.w700, color: dewTeal)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final w in words)
                      ActionChip(
                        label: Text(w),
                        onPressed: () async {
                          setS(() {
                            selected = w;
                            result = '...';
                          });
                          final t = await Translator.translate(w, AppSettings.targetLang);
                          setS(() => result = t ?? 'Translation failed (no internet?)');
                        },
                      ),
                  ],
                ),
                if (selected != null) ...[
                  const SizedBox(height: 16),
                  Text(selected!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(result ?? '', style: const TextStyle(fontSize: 18, color: dewSky)),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}
