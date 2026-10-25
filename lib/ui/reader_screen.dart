import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../audio/reader_handler.dart';
import '../services/segmenter.dart';
import 'voice_sheet.dart';

/// The document text with the current sentence highlighted, plus controls.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ReaderHandler h = widget.state.handler;
  late List<_Para> _paras;
  late List<GlobalKey> _keys;
  final _scroll = ScrollController();
  bool _follow = true;

  void _load() {
    _paras = _group(h.segments);
    _keys = List.generate(_paras.length, (_) => GlobalKey());
  }

  /// Another document was opened (next/previous document).
  void _onDocChanged() {
    if (!mounted) return;
    setState(() {
      _load();
      _follow = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(animate: false),
    );
  }

  Future<void> _switchDoc(bool next) async {
    final moved = next ? await h.nextDocument() : await h.previousDocument();
    if (!moved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'This is the last document in your list.'
                : 'This is the first document in your list.',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    h.docVersion.addListener(_onDocChanged);
    h.index.addListener(_onIndex);
    h.error.addListener(_onError);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(animate: false),
    );
  }

  @override
  void dispose() {
    h.docVersion.removeListener(_onDocChanged);
    h.index.removeListener(_onIndex);
    h.error.removeListener(_onError);
    _scroll.dispose();
    super.dispose();
  }

  static List<_Para> _group(List<Segment> segs) {
    final out = <_Para>[];
    for (var i = 0; i < segs.length; i++) {
      if (out.isEmpty || out.last.paragraph != segs[i].paragraph) {
        out.add(_Para(segs[i].paragraph, i));
      }
      out.last.texts.add(segs[i].text);
    }
    return out;
  }

  int _paraIndexOf(int segment) {
    var lo = 0, hi = _paras.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_paras[mid].first <= segment) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void _onIndex() {
    if (_follow) _scrollToCurrent();
  }

  void _onError() {
    final e = h.error.value;
    if (e == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
    h.error.value = null;
  }

  void _scrollToCurrent({bool animate = true}) {
    if (_paras.isEmpty) return;
    final ctx = _keys[_paraIndexOf(h.index.value)].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.25,
      duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          h.doc?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Voice and speed',
            icon: const Icon(Icons.record_voice_over),
            onPressed: () => showVoiceSheet(context, h),
          ),
        ],
      ),
      body: Stack(
        children: [
          NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              if (n.direction != ScrollDirection.idle && _follow) {
                setState(() => _follow = false);
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _paras.length; i++)
                    Padding(
                      key: _keys[i],
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ParagraphText(
                        para: _paras[i],
                        index: h.index,
                        onTap: (seg) async {
                          await h.jumpTo(seg);
                          if (!h.playing.value) await h.play();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_follow)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                tooltip: 'Back to where it\'s reading',
                onPressed: () {
                  setState(() => _follow = true);
                  _scrollToCurrent();
                },
                child: const Icon(Icons.my_location),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          color: scheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: h.index,
                  builder: (_, i, _) => Text(
                    h.segments.isEmpty
                        ? ''
                        : 'Sentence ${i + 1} of ${h.segments.length}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Doc'),
                      onPressed: () => _switchDoc(false),
                    ),
                    IconButton(
                      tooltip: 'Start of document',
                      icon: const Icon(Icons.vertical_align_top),
                      onPressed: h.toStart,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'End of document',
                      icon: const Icon(Icons.vertical_align_bottom),
                      onPressed: h.toEnd,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Doc'),
                      iconAlignment: IconAlignment.end,
                      onPressed: () => _switchDoc(true),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Previous paragraph',
                      iconSize: 30,
                      icon: const Icon(Icons.keyboard_double_arrow_left),
                      onPressed: h.previousParagraph,
                    ),
                    IconButton(
                      tooltip: 'Previous sentence',
                      iconSize: 30,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: h.skipToPrevious,
                    ),
                    _PlayButton(h: h),
                    IconButton(
                      tooltip: 'Next sentence',
                      iconSize: 30,
                      icon: const Icon(Icons.skip_next),
                      onPressed: h.skipToNext,
                    ),
                    IconButton(
                      tooltip: 'Next paragraph',
                      iconSize: 30,
                      icon: const Icon(Icons.keyboard_double_arrow_right),
                      onPressed: h.nextParagraph,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Para {
  _Para(this.paragraph, this.first);
  final int paragraph;
  final int first; // index of its first sentence
  final texts = <String>[];
}

/// One paragraph; rebuilds only when the highlight enters, moves within or
/// leaves it.
class _ParagraphText extends StatefulWidget {
  const _ParagraphText({
    required this.para,
    required this.index,
    required this.onTap,
  });
  final _Para para;
  final ValueNotifier<int> index;
  final void Function(int segment) onTap;

  @override
  State<_ParagraphText> createState() => _ParagraphTextState();
}

class _ParagraphTextState extends State<_ParagraphText> {
  late int _active = _activeFor(widget.index.value);
  final _recognizers = <TapGestureRecognizer>[];

  int _activeFor(int i) {
    final local = i - widget.para.first;
    return local >= 0 && local < widget.para.texts.length ? local : -1;
  }

  void _listen() {
    final a = _activeFor(widget.index.value);
    if (a != _active) setState(() => _active = a);
  }

  @override
  void initState() {
    super.initState();
    widget.index.addListener(_listen);
    for (var k = 0; k < widget.para.texts.length; k++) {
      _recognizers.add(
        TapGestureRecognizer()
          ..onTap = () => widget.onTap(widget.para.first + k),
      );
    }
  }

  @override
  void dispose() {
    widget.index.removeListener(_listen);
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!.copyWith(height: 1.5, fontSize: 18);
    final hl = base.copyWith(
      backgroundColor: theme.colorScheme.primaryContainer,
      color: theme.colorScheme.onPrimaryContainer,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (var k = 0; k < widget.para.texts.length; k++)
            TextSpan(
              text: '${widget.para.texts[k]} ',
              style: k == _active ? hl : base,
              recognizer: _recognizers[k],
            ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.h});
  final ReaderHandler h;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: h.playing,
      builder: (_, playing, _) => ValueListenableBuilder<bool>(
        valueListenable: h.waiting,
        builder: (_, waiting, _) => SizedBox(
          width: 68,
          height: 68,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (playing && waiting)
                const SizedBox(
                  width: 68,
                  height: 68,
                  child: CircularProgressIndicator(),
                ),
              IconButton.filled(
                tooltip: playing ? 'Pause' : 'Play',
                iconSize: 40,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: playing ? h.pause : h.play,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
