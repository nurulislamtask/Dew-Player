import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'ai_subtitles.dart';
import 'app_settings.dart';
import 'home_page.dart' show fmtDuration;
import 'languages.dart';
import 'library.dart';
import 'settings_page.dart' show pickLanguage;
import 'subtitles.dart';
import 'translator.dart';

class PlayerPage extends StatefulWidget {
  final List<VideoItem> items;
  final int index;
  const PlayerPage({super.key, required this.items, required this.index});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  final subs = <StreamSubscription>[];

  final pos = ValueNotifier<Duration>(Duration.zero);
  final dragValue = ValueNotifier<double?>(null);
  final subTop = ValueNotifier<String>('');
  final subBottom = ValueNotifier<String>('');
  final hint = ValueNotifier<String>('');
  final aiStatus = ValueNotifier<String>('');

  late int idx = widget.index;
  String source = '';
  String title = '';
  Duration duration = Duration.zero;
  bool playing = true;
  bool buffering = false;
  bool showControls = true;
  bool locked = false;
  bool fullscreen = false;
  double rate = 1.0;
  double volume = 100;
  double brightness = 0.5;
  int fitIndex = 0;
  int orientIndex = 0;
  BoxFit get fit => const [BoxFit.contain, BoxFit.cover, BoxFit.fill][fitIndex];
  Timer? hideTimer;
  Timer? hintTimer;
  Timer? autoSubTimer;
  Timer? saveTimer;
  bool resumed = false;

  // subtitles
  List<SubLine> lines = [];
  String embeddedText = '';
  String origText = '';
  String transText = '';
  int _reqId = 0;
  int _prefetchedFor = -2;
  AiSubtitleGenerator ai = AiSubtitleGenerator();

  // gesture state
  double _hdx = 0;
  Duration _hStart = Duration.zero;
  bool _hSeeking = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      ScreenBrightness.instance.application.then((v) => brightness = v).catchError((_) => 0.5);
    }
    WakelockPlus.enable();

    subs.add(player.stream.position.listen((d) {
      pos.value = d;
      _tick(d);
    }));
    subs.add(player.stream.duration.listen((d) {
      duration = d;
      if (d > Duration.zero && !resumed) {
        resumed = true;
        final r = AppSettings.resumeFor(source);
        if (r != null && r > const Duration(seconds: 8) && r < d - const Duration(seconds: 10)) {
          player.seek(r);
          _toast('Resumed at ${fmtDuration(r)}');
        }
      }
      if (mounted) setState(() {});
    }));
    subs.add(player.stream.playing.listen((p) {
      if (mounted) setState(() => playing = p);
      _scheduleHide();
    }));
    subs.add(player.stream.buffering.listen((b) {
      if (mounted) setState(() => buffering = b);
    }));
    subs.add(player.stream.completed.listen((c) {
      if (c && idx < widget.items.length - 1) _go(idx + 1);
    }));
    subs.add(player.stream.subtitle.listen((l) {
      embeddedText = l.where((e) => e.trim().isNotEmpty).join('\n');
      _tick(pos.value);
    }));
    subs.add(player.stream.tracks.listen((_) {
      if (mounted) setState(() {});
    }));
    saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveResume());

    _load(idx);
  }

  @override
  void dispose() {
    _saveResume();
    hideTimer?.cancel();
    hintTimer?.cancel();
    autoSubTimer?.cancel();
    saveTimer?.cancel();
    for (final s in subs) {
      s.cancel();
    }
    ai.cancel();
    player.dispose();
    WakelockPlus.disable();
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    }
    if (Platform.isWindows && fullscreen) windowManager.setFullScreen(false);
    super.dispose();
  }

  void _saveResume() {
    if (source.isEmpty) return;
    AppSettings.saveResume(source, pos.value, duration);
  }

  // ---------- loading ----------
  Future<void> _load(int i) async {
    _saveResume();
    ai.cancel();
    ai = AiSubtitleGenerator();
    autoSubTimer?.cancel();
    final item = widget.items[i];
    final path = await item.resolve();
    if (!mounted) return;
    if (path == null) {
      _toast('Cannot open this video');
      return;
    }
    setState(() {
      idx = i;
      source = path;
      title = item.title;
      resumed = false;
      lines = [];
      embeddedText = '';
      origText = '';
      transText = '';
      aiStatus.value = '';
    });
    _refreshDisplay();
    pos.value = Duration.zero;
    await player.open(Media(path), play: true);
    player.setRate(rate);
    _scheduleHide();
    _sideloadSubtitle(path);
    autoSubTimer = Timer(const Duration(seconds: 3), _maybeAutoSubs);
  }

  void _go(int i) {
    if (i < 0 || i >= widget.items.length) return;
    _load(i);
  }

  /// Uses movie.srt/.vtt/.ass that sits next to movie.mp4.
  Future<void> _sideloadSubtitle(String path) async {
    if (path.startsWith('http') || path.startsWith('rtsp') || path.startsWith('rtmp')) return;
    final dot = path.lastIndexOf('.');
    if (dot < 0) return;
    final base = path.substring(0, dot);
    for (final ext in ['srt', 'vtt', 'ass', 'ssa']) {
      final f = File('$base.$ext');
      try {
        if (await f.exists()) {
          final l = await loadSubtitleFile(f.path);
          if (l.isNotEmpty && mounted && source == path) {
            lines = l;
            _tick(pos.value);
            return;
          }
        }
      } catch (_) {}
    }
  }

  void _maybeAutoSubs() {
    if (!mounted || ai.running || lines.isNotEmpty) return;
    final tracks = player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (tracks.isNotEmpty) {
      // the video has its own subtitles: make sure one is on
      if (player.state.track.subtitle.id == 'no') player.setSubtitleTrack(tracks.first);
      return;
    }
    if (AppSettings.autoSubs) _startAi();
  }

  // ---------- subtitles ----------
  String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  void _tick(Duration d) {
    final p = lines.isNotEmpty ? lineAt(lines, d) : embeddedText;
    if (p != origText) {
      origText = p;
      transText = '';
      _refreshDisplay();
      _translateCurrent(p);
      if (lines.isNotEmpty) _prefetch(d);
    }
  }

  Future<void> _translateCurrent(String p) async {
    if (!AppSettings.translateSubs || p.isEmpty) return;
    final id = ++_reqId;
    final t = await Translator.translate(p, AppSettings.targetLang);
    if (!mounted || id != _reqId) return;
    transText = t ?? '';
    _refreshDisplay();
  }

  /// Translate the next few lines early so they appear without delay.
  void _prefetch(Duration d) {
    if (!AppSettings.translateSubs) return;
    final i = indexAt(lines, d);
    if (i == _prefetchedFor) return;
    _prefetchedFor = i;
    for (var k = i + 1; k <= i + 4 && k < lines.length; k++) {
      Translator.translate(lines[k].text, AppSettings.targetLang);
    }
  }

  void _refreshDisplay() {
    final o = origText;
    final t = transText;
    final translating = AppSettings.translateSubs && o.isNotEmpty && t.isNotEmpty;
    var top = '';
    var bottom = '';
    switch (AppSettings.subMode) {
      case SubMode.original:
        bottom = o;
        break;
      case SubMode.translated:
        bottom = translating ? t : o;
        break;
      case SubMode.both:
        if (translating && _norm(t) != _norm(o)) {
          top = o;
          bottom = t;
        } else {
          bottom = o;
        }
        break;
    }
    subTop.value = top;
    subBottom.value = bottom;
  }

  void _settingsChanged() {
    transText = '';
    _prefetchedFor = -2;
    _refreshDisplay();
    _translateCurrent(origText);
    if (mounted) setState(() {});
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

  void _startAi() {
    if (ai.running) return;
    player.setSubtitleTrack(SubtitleTrack.no());
    lines = [];
    final gen = <SubLine>[];
    final mine = ai;
    mine
        .start(
          source: source,
          from: pos.value,
          model: AppSettings.aiModel,
          onLines: (l) {
            if (!mounted || mine != ai) return;
            gen.addAll(l);
            lines = List.of(gen);
            _tick(pos.value);
          },
          onStatus: (t) {
            if (!mounted || mine != ai) return;
            aiStatus.value = t;
            if (t.contains('finished') || t.contains('stopped') || t.contains('failed')) {
              Future.delayed(const Duration(seconds: 6), () {
                if (mounted && !mine.running) aiStatus.value = '';
              });
            }
          },
        )
        .catchError((e) {
      if (mounted) aiStatus.value = 'AI subtitles failed: $e';
    });
  }

  // ---------- controls ----------
  void _toast(String text) {
    hint.value = text;
    hintTimer?.cancel();
    hintTimer = Timer(const Duration(milliseconds: 1000), () => hint.value = '');
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

  void _toggleFullscreen() {
    if (!Platform.isWindows) return;
    fullscreen = !fullscreen;
    windowManager.setFullScreen(fullscreen);
    setState(() {});
  }

  void _cycleOrientation() {
    orientIndex = (orientIndex + 1) % 3;
    const names = ['Auto rotate', 'Landscape', 'Portrait'];
    final modes = [
      DeviceOrientation.values,
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      [DeviceOrientation.portraitUp],
    ];
    SystemChrome.setPreferredOrientations(modes[orientIndex]);
    _toast(names[orientIndex]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      player.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      volume = (volume + 5).clamp(0, 100).toDouble();
      player.setVolume(volume);
      _toast('Volume ${volume.round()}%');
    } else if (k == LogicalKeyboardKey.arrowDown) {
      volume = (volume - 5).clamp(0, 100).toDouble();
      player.setVolume(volume);
      _toast('Volume ${volume.round()}%');
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.escape) {
      if (fullscreen) {
        _toggleFullscreen();
      } else {
        Navigator.pop(context);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: controller,
              controls: NoVideoControls,
              fit: fit,
              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
            ),
            _gestureLayer(),
            _subtitleOverlay(),
            if (buffering) Center(child: CircularProgressIndicator(color: accent)),
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
                        child: Text(v, style: const TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: aiStatus,
              builder: (_, v, __) => v.isEmpty
                  ? const SizedBox.shrink()
                  : Positioned(
                      top: MediaQuery.of(context).padding.top + 56,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
                            const SizedBox(width: 6),
                            Text(v, style: TextStyle(fontSize: 12, color: accent)),
                          ],
                        ),
                      ),
                    ),
            ),
            if (locked)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.lock_open_rounded),
                      onPressed: () => setState(() {
                        locked = false;
                        showControls = true;
                        _scheduleHide();
                      }),
                    ),
                  ),
                ),
              )
            else
              AnimatedOpacity(
                opacity: showControls ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(ignoring: !showControls, child: _controls(accent)),
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
        onDoubleTapDown: locked
            ? null
            : (d) => _seekBy(d.localPosition.dx < c.maxWidth / 2 ? -10 : 10),
        onDoubleTap: () {},
        onLongPressStart: locked
            ? null
            : (_) {
                player.setRate(2.0);
                _toast('2x');
              },
        onLongPressEnd: locked ? null : (_) => player.setRate(rate),
        onVerticalDragUpdate: locked
            ? null
            : (d) {
                final delta = -d.delta.dy / (c.maxHeight * 0.6);
                if (d.localPosition.dx > c.maxWidth / 2) {
                  volume = (volume + delta * 100).clamp(0, 100).toDouble();
                  player.setVolume(volume);
                  _toast('Volume ${volume.round()}%');
                } else if (Platform.isAndroid) {
                  brightness = (brightness + delta).clamp(0.02, 1.0).toDouble();
                  ScreenBrightness.instance.setApplicationScreenBrightness(brightness).catchError((_) {});
                  _toast('Brightness ${(brightness * 100).round()}%');
                }
              },
        onHorizontalDragStart: locked
            ? null
            : (_) {
                _hdx = 0;
                _hStart = pos.value;
                _hSeeking = true;
              },
        onHorizontalDragUpdate: locked
            ? null
            : (d) {
                if (!_hSeeking) return;
                _hdx += d.delta.dx;
                final secs = (_hdx / c.maxWidth * 120).round();
                var t = _hStart + Duration(seconds: secs);
                if (t < Duration.zero) t = Duration.zero;
                if (duration > Duration.zero && t > duration) t = duration;
                _toast('${fmtDuration(t)}  (${secs >= 0 ? '+' : ''}${secs}s)');
              },
        onHorizontalDragEnd: locked
            ? null
            : (_) {
                if (!_hSeeking) return;
                _hSeeking = false;
                final secs = (_hdx / MediaQuery.of(context).size.width * 120).round();
                var t = _hStart + Duration(seconds: secs);
                if (t < Duration.zero) t = Duration.zero;
                if (duration > Duration.zero && t > duration) t = duration;
                player.seek(t);
              },
      );
    });
  }

  Widget _subtitleOverlay() {
    final size = AppSettings.subSize;
    Widget line(String text, double fs, Color color) {
      return Container(
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(100),
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
      );
    }

    return Positioned(
      left: 24,
      right: 24,
      bottom: (showControls && !locked) ? 84 : 24,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: subTop,
              builder: (_, s, __) => s.isEmpty
                  ? const SizedBox.shrink()
                  : line(s, size - 3, const Color(0xFFE5E7EB)),
            ),
            ValueListenableBuilder<String>(
              valueListenable: subBottom,
              builder: (_, s, __) =>
                  s.isEmpty ? const SizedBox.shrink() : line(s, size, Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(Color accent) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(top: top + 4, left: 4, right: 4, bottom: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.subtitles_rounded),
                    tooltip: 'Subtitles',
                    onPressed: _subtitleMenu,
                  ),
                  IconButton(
                    icon: const Icon(Icons.audiotrack_rounded),
                    tooltip: 'Audio',
                    onPressed: _audioMenu,
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'More',
                    onPressed: _moreMenu,
                  ),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: idx > 0 ? () => _go(idx - 1) : null,
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  iconSize: 44,
                  style: IconButton.styleFrom(
                    backgroundColor: accent.withAlpha(230),
                    foregroundColor: Colors.black,
                  ),
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: () {
                    player.playOrPause();
                    _scheduleHide();
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: idx < widget.items.length - 1 ? () => _go(idx + 1) : null,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.only(left: 16, right: 4, bottom: bottom + 4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: ValueListenableBuilder<Duration>(
                  valueListenable: pos,
                  builder: (_, p, __) {
                    final total = duration.inMilliseconds.toDouble();
                    final max = total > 0 ? total : 1.0;
                    final cur = p.inMilliseconds.toDouble().clamp(0, max).toDouble();
                    return ValueListenableBuilder<double?>(
                      valueListenable: dragValue,
                      builder: (_, drag, __) {
                        final shown = (drag ?? cur).clamp(0, max).toDouble();
                        return Row(
                          children: [
                            Text(fmtDuration(Duration(milliseconds: shown.round()))),
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: max,
                                value: shown,
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
                            Text(fmtDuration(duration)),
                            IconButton(
                              icon: const Icon(Icons.lock_outline_rounded),
                              tooltip: 'Lock',
                              onPressed: () => setState(() {
                                locked = true;
                                showControls = true;
                                _scheduleHide();
                              }),
                            ),
                            if (Platform.isWindows)
                              IconButton(
                                icon: Icon(fullscreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded),
                                tooltip: 'Fullscreen (F)',
                                onPressed: _toggleFullscreen,
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- sheets ----------
  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      );

  Widget _check(bool on) => on
      ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary)
      : const SizedBox.shrink();

  void _sheet(Widget Function(BuildContext, StateSetter) builder) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: builder(ctx, setS),
          ),
        ),
      ),
    );
  }

  void _subtitleMenu() {
    _sheet((ctx, setS) {
      final embedded = player.state.tracks.subtitle
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList();
      final curId = player.state.track.subtitle.id;
      final usingExternal = lines.isNotEmpty;
      return ListView(
        shrinkWrap: true,
        children: [
          _title('Subtitle'),
          ListTile(
            leading: const Icon(Icons.subtitles_off_rounded),
            title: const Text('Off'),
            trailing: _check(!usingExternal && curId == 'no'),
            onTap: () {
              ai.cancel();
              lines = [];
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
              trailing: _check(!usingExternal && curId == t.id),
              onTap: () {
                lines = [];
                player.setSubtitleTrack(t);
                setS(() {});
              },
            ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('Load subtitle file...'),
            subtitle: const Text('srt, vtt, ass'),
            onTap: () async {
              final l = await _pickSubtitleFile();
              if (l != null) {
                ai.cancel();
                lines = l;
                player.setSubtitleTrack(SubtitleTrack.no());
                _tick(pos.value);
                setS(() {});
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_rounded),
            title: Text(ai.running ? 'Stop AI subtitles' : 'Create subtitles with AI'),
            subtitle: const Text('Any language, works offline after the first download'),
            onTap: () {
              Navigator.pop(ctx);
              if (ai.running) {
                ai.cancel();
              } else {
                _startAi();
              }
            },
          ),
          const Divider(),
          _title('Translate'),
          SwitchListTile(
            secondary: const Icon(Icons.translate_rounded),
            title: const Text('Translate subtitles'),
            subtitle: const Text('Needs internet'),
            value: AppSettings.translateSubs,
            onChanged: (v) {
              AppSettings.translateSubs = v;
              _settingsChanged();
              setS(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('Translate to'),
            subtitle: Text(languageName(AppSettings.targetLang)),
            onTap: () async {
              final c = await pickLanguage(context, AppSettings.targetLang);
              if (c != null) {
                AppSettings.targetLang = c;
                _settingsChanged();
                setS(() {});
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.view_agenda_outlined),
            title: const Text('Show'),
            trailing: DropdownButton<SubMode>(
              value: AppSettings.subMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: SubMode.translated, child: Text('Translated only')),
                DropdownMenuItem(value: SubMode.both, child: Text('Both lines')),
                DropdownMenuItem(value: SubMode.original, child: Text('Original only')),
              ],
              onChanged: (v) {
                AppSettings.subMode = v!;
                _refreshDisplay();
                setS(() {});
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.format_size_rounded),
            title: Slider(
              min: 12,
              max: 36,
              value: AppSettings.subSize,
              onChanged: (v) {
                AppSettings.subSize = v;
                setS(() {});
                setState(() {});
              },
            ),
          ),
        ],
      );
    });
  }

  void _audioMenu() {
    _sheet((ctx, setS) {
      final tracks = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
      final curId = player.state.track.audio.id;
      return ListView(
        shrinkWrap: true,
        children: [
          _title('Audio track'),
          if (tracks.isEmpty) const ListTile(title: Text('No other audio tracks')),
          for (final t in tracks)
            ListTile(
              leading: const Icon(Icons.audiotrack_rounded),
              title: Text(t.title ?? t.language ?? 'Track ${t.id}'),
              subtitle: t.language != null ? Text(t.language!) : null,
              trailing: _check(curId == t.id),
              onTap: () {
                player.setAudioTrack(t);
                setS(() {});
              },
            ),
        ],
      );
    });
  }

  void _moreMenu() {
    _sheet((ctx, setS) {
      const fits = ['Fit', 'Fill (crop)', 'Stretch'];
      return ListView(
        shrinkWrap: true,
        children: [
          _title('Speed'),
          Wrap(
            spacing: 8,
            children: [
              for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                ChoiceChip(
                  label: Text('${r}x'),
                  selected: rate == r,
                  onSelected: (_) {
                    rate = r;
                    player.setRate(r);
                    setS(() {});
                  },
                ),
            ].map((w) => Padding(padding: const EdgeInsets.only(left: 8), child: w)).toList(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.aspect_ratio_rounded),
            title: const Text('Screen'),
            trailing: Text(fits[fitIndex]),
            onTap: () {
              setState(() => fitIndex = (fitIndex + 1) % 3);
              setS(() {});
            },
          ),
          if (Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.screen_rotation_rounded),
              title: const Text('Rotation'),
              trailing: Text(['Auto', 'Landscape', 'Portrait'][orientIndex]),
              onTap: () {
                _cycleOrientation();
                setS(() {});
              },
            ),
        ],
      );
    });
  }
}
